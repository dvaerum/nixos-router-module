use crate::error::Result;
use async_trait::async_trait;
use std::collections::HashMap;
use std::path::PathBuf;
use walkdir::WalkDir;

/// Seam for `PxeBootService` (C33) -- lets tests inject a `FakeIsoDiscovery`
/// instead of scanning a real directory tree.
#[async_trait]
pub trait IsoDiscovering: Send + Sync {
    async fn discover(&self) -> Result<Vec<PathBuf>>;
}

pub struct IsoDiscovery {
    iso_folders: Vec<PathBuf>,
}

impl IsoDiscovery {
    pub fn new(iso_folders: Vec<PathBuf>) -> Self {
        Self { iso_folders }
    }

    /// Discover all ISO files across every configured source directory
    /// (typically a user-managed manual directory plus, optionally, a
    /// Nix-managed `tmpfiles "L+"` symlink farm of store-built ISOs),
    /// merging the results. If the same filename exists in more than one
    /// source directory, the first match wins (by `iso_folders` list
    /// order) and the duplicate is dropped with a warning naming both --
    /// not a hard error, since a stale or overlapping manual copy
    /// shouldn't block every other ISO from booting.
    pub async fn discover(&self) -> Result<Vec<PathBuf>> {
        let iso_folders = self.iso_folders.clone();

        // Run blocking walkdir in a spawn_blocking task
        let isos = tokio::task::spawn_blocking(move || {
            let mut seen: HashMap<String, PathBuf> = HashMap::new();

            for iso_folder in &iso_folders {
                let mut found_in_this_folder = Vec::new();

                for entry in WalkDir::new(iso_folder).max_depth(1).into_iter() {
                    let entry = match entry {
                        Ok(entry) => entry,
                        Err(e) => {
                            // Previously silently dropped via
                            // `.filter_map(|e| e.ok())` -- a
                            // permission-denied entry (or similar) would
                            // vanish with zero trace.
                            tracing::warn!(
                                "Skipping unreadable entry while scanning {}: {}",
                                iso_folder.display(),
                                e
                            );
                            continue;
                        }
                    };

                    // Previously relied solely on `.extension()`, which
                    // would match a directory literally named e.g.
                    // "stale.iso" just as readily as a real file -- that
                    // directory would then get queued for mounting
                    // downstream.
                    //
                    // `entry.file_type()` reports the symlink's own type,
                    // not what it points to -- every entry in a
                    // `pkgs.linkFarm`-populated `nixIsos` directory is a
                    // symlink, so that check silently filtered out all
                    // of them. `path().metadata()` follows the link.
                    let is_file = entry
                        .path()
                        .metadata()
                        .map(|m| m.is_file())
                        .unwrap_or(false);
                    if !is_file {
                        continue;
                    }

                    if let Some(ext) = entry.path().extension() {
                        if ext.eq_ignore_ascii_case("iso") {
                            found_in_this_folder.push(entry.path().to_path_buf());
                        }
                    }
                }

                // Deterministic within-folder ordering before the
                // cross-folder dedup below, so "first match wins" is
                // reproducible rather than dependent on readdir order.
                found_in_this_folder.sort();

                for path in found_in_this_folder {
                    let file_name = path
                        .file_name()
                        .map(|n| n.to_string_lossy().to_string())
                        .unwrap_or_default();

                    if let Some(existing) = seen.get(&file_name) {
                        tracing::warn!(
                            "Duplicate ISO filename '{}' found in multiple source directories -- keeping {} (first match, by iso_folder_paths list order), ignoring {}",
                            file_name,
                            existing.display(),
                            path.display()
                        );
                    } else {
                        seen.insert(file_name, path);
                    }
                }
            }

            // Sort for deterministic ordering
            let mut isos: Vec<PathBuf> = seen.into_values().collect();
            isos.sort();
            isos
        })
        .await
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;

        Ok(isos)
    }
}

#[async_trait]
impl IsoDiscovering for IsoDiscovery {
    async fn discover(&self) -> Result<Vec<PathBuf>> {
        IsoDiscovery::discover(self).await
    }
}

/// Test double for [`IsoDiscovering`] -- `pub` (not nested in `mod tests`)
/// so `lib.rs`'s own test module can use it too, unlike `FakeDetector`
/// (distro/detector.rs), which only ever needed to be used from its own
/// file.
#[cfg(test)]
pub struct FakeIsoDiscovery {
    isos: Vec<PathBuf>,
}

#[cfg(test)]
impl FakeIsoDiscovery {
    pub fn returning(isos: Vec<PathBuf>) -> Self {
        Self { isos }
    }
}

#[cfg(test)]
#[async_trait]
impl IsoDiscovering for FakeIsoDiscovery {
    async fn discover(&self) -> Result<Vec<PathBuf>> {
        Ok(self.isos.clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[tokio::test]
    async fn discovers_iso_files_case_insensitively() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("foo.iso"), b"a").unwrap();
        fs::write(dir.path().join("bar.ISO"), b"b").unwrap();
        fs::write(dir.path().join("readme.txt"), b"c").unwrap();

        let discovery = IsoDiscovery::new(vec![dir.path().to_path_buf()]);
        let isos = discovery.discover().await.unwrap();

        assert_eq!(isos.len(), 2);
        assert!(isos.iter().any(|p| p.ends_with("foo.iso")));
        assert!(isos.iter().any(|p| p.ends_with("bar.ISO")));
    }

    #[tokio::test]
    async fn ignores_directories_named_like_an_iso() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir(dir.path().join("stale.iso")).unwrap();
        fs::write(dir.path().join("real.iso"), b"a").unwrap();

        let discovery = IsoDiscovery::new(vec![dir.path().to_path_buf()]);
        let isos = discovery.discover().await.unwrap();

        assert_eq!(isos.len(), 1);
        assert!(isos[0].ends_with("real.iso"));
    }

    #[tokio::test]
    async fn does_not_recurse_into_subdirectories() {
        let dir = tempfile::tempdir().unwrap();
        let nested = dir.path().join("nested");
        fs::create_dir(&nested).unwrap();
        fs::write(nested.join("hidden.iso"), b"a").unwrap();
        fs::write(dir.path().join("top.iso"), b"b").unwrap();

        let discovery = IsoDiscovery::new(vec![dir.path().to_path_buf()]);
        let isos = discovery.discover().await.unwrap();

        assert_eq!(isos.len(), 1);
        assert!(isos[0].ends_with("top.iso"));
    }

    #[tokio::test]
    async fn merges_results_from_multiple_source_folders() {
        let a = tempfile::tempdir().unwrap();
        let b = tempfile::tempdir().unwrap();
        fs::write(a.path().join("alpha.iso"), b"a").unwrap();
        fs::write(b.path().join("beta.iso"), b"b").unwrap();

        let discovery = IsoDiscovery::new(vec![a.path().to_path_buf(), b.path().to_path_buf()]);
        let isos = discovery.discover().await.unwrap();

        assert_eq!(isos.len(), 2);
        assert!(isos.iter().any(|p| p.ends_with("alpha.iso")));
        assert!(isos.iter().any(|p| p.ends_with("beta.iso")));
    }

    #[tokio::test]
    async fn discovers_symlinked_iso_files() {
        // Mirrors the real `nixIsos` shape: `pkgs.linkFarm` populates the
        // source directory entirely with symlinks pointing at files
        // elsewhere (e.g. the Nix store). walkdir's default
        // `file_type()` reports the *symlink's own* type, not the type
        // of what it points to, so a naive `is_file()` check silently
        // skips every one of these.
        let target_dir = tempfile::tempdir().unwrap();
        let real_iso = target_dir.path().join("real-target.iso");
        fs::write(&real_iso, b"a").unwrap();

        let farm_dir = tempfile::tempdir().unwrap();
        std::os::unix::fs::symlink(&real_iso, farm_dir.path().join("linked.iso")).unwrap();

        let discovery = IsoDiscovery::new(vec![farm_dir.path().to_path_buf()]);
        let isos = discovery.discover().await.unwrap();

        assert_eq!(isos.len(), 1);
        assert!(isos[0].ends_with("linked.iso"));
    }

    #[tokio::test]
    async fn first_folder_wins_on_duplicate_filename() {
        let first = tempfile::tempdir().unwrap();
        let second = tempfile::tempdir().unwrap();
        fs::write(first.path().join("same.iso"), b"from-first").unwrap();
        fs::write(second.path().join("same.iso"), b"from-second").unwrap();

        let discovery =
            IsoDiscovery::new(vec![first.path().to_path_buf(), second.path().to_path_buf()]);
        let isos = discovery.discover().await.unwrap();

        assert_eq!(isos.len(), 1);
        assert_eq!(isos[0], first.path().join("same.iso"));
    }

    #[tokio::test]
    async fn first_folder_wins_across_three_source_folders() {
        // The existing two-folder test can't distinguish "first wins"
        // from "last-processed wins" when there are only two candidates
        // and HashMap insertion order happens to match. A third folder
        // makes the list-order claim unambiguous.
        let first = tempfile::tempdir().unwrap();
        let second = tempfile::tempdir().unwrap();
        let third = tempfile::tempdir().unwrap();
        fs::write(first.path().join("same.iso"), b"from-first").unwrap();
        fs::write(second.path().join("same.iso"), b"from-second").unwrap();
        fs::write(third.path().join("same.iso"), b"from-third").unwrap();

        let discovery = IsoDiscovery::new(vec![
            first.path().to_path_buf(),
            second.path().to_path_buf(),
            third.path().to_path_buf(),
        ]);
        let isos = discovery.discover().await.unwrap();

        assert_eq!(isos.len(), 1);
        assert_eq!(isos[0], first.path().join("same.iso"));
    }
}
