use crate::error::{IoResultExt, Result};
use std::path::PathBuf;


/// Maintains `runtime_root/isos/` as a canonical, flat symlink tree: one
/// symlink per discovered ISO, pointing back to wherever it was actually
/// found (any of the configured `iso_folder_paths`). This gives the HTTP
/// server one single, static directory to serve raw whole-ISO downloads
/// from (e.g. Ubuntu/casper's `url=` fetch), regardless of how many real
/// source directories (a manual directory, a Nix-managed `tmpfiles "L+"`
/// symlink farm, etc.) feed discovery -- mirrors the pattern `IsoMounter`
/// already uses for the GRUB-serving side (one canonical
/// `runtime_root/iso-mountpoint/<name>` tree regardless of source).
pub struct ServeTree {
    isos_dir: PathBuf,
}

impl ServeTree {
    pub fn new(runtime_root: PathBuf) -> Self {
        Self {
            isos_dir: runtime_root.join("isos"),
        }
    }

    pub fn isos_dir(&self) -> &PathBuf {
        &self.isos_dir
    }

    /// Rebuilds the tree from scratch: builds a fresh tree in a sibling
    /// `isos.new` directory, then atomically swaps it into place --
    /// creates one symlink per entry in `iso_paths`. Building into a
    /// sibling directory and renaming over the final location (rather
    /// than wiping `isos_dir` in place and repopulating it) means a
    /// crash or panic partway through leaves the PREVIOUS complete tree
    /// intact instead of a truncated one: the old tree is only ever
    /// removed in the same breath as the already-fully-built replacement
    /// taking its place.
    pub async fn rebuild(&self, iso_paths: &[PathBuf]) -> Result<()> {
        let tmp_dir = self.isos_dir.with_file_name("isos.new");

        // Clean up any leftover partial build from a previous crashed
        // run before starting a fresh one.
        if tmp_dir.exists() {
            tokio::fs::remove_dir_all(&tmp_dir).await.with_path(&tmp_dir)?;
        }
        tokio::fs::create_dir_all(&tmp_dir).await.with_path(&tmp_dir)?;

        // C34: each symlink is an independent write to its own path under
        // `tmp_dir` -- unlike ISO mounting (see lib.rs's prepare(), kept
        // strictly sequential after a real kernel-level loop-device race),
        // nothing here shares mutable OS-level state across ISOs, so
        // fanning these out concurrently is safe.
        let results = futures::future::join_all(iso_paths.iter().filter_map(|iso_path| {
            let file_name = iso_path.file_name()?;
            let link_path = tmp_dir.join(file_name);
            let iso_path = iso_path.clone();
            Some(async move {
                tokio::fs::symlink(&iso_path, &link_path)
                    .await
                    .with_path(&link_path)
            })
        }))
        .await;
        for result in results {
            result?;
        }

        if self.isos_dir.exists() {
            tokio::fs::remove_dir_all(&self.isos_dir)
                .await
                .with_path(&self.isos_dir)?;
        }
        tokio::fs::rename(&tmp_dir, &self.isos_dir)
            .await
            .with_path(&self.isos_dir)?;

        Ok(())
    }
}


#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[tokio::test]
    async fn creates_a_symlink_per_iso() {
        let rt = tempfile::tempdir().unwrap();
        let source = tempfile::tempdir().unwrap();
        let iso_path = source.path().join("foo.iso");
        fs::write(&iso_path, b"iso bytes").unwrap();

        let tree = ServeTree::new(rt.path().to_path_buf());
        tree.rebuild(std::slice::from_ref(&iso_path)).await.unwrap();

        let link = rt.path().join("isos").join("foo.iso");
        assert_eq!(fs::read_link(&link).unwrap(), iso_path);
        // The symlink must actually resolve to real content, not just
        // exist as a dangling link.
        assert_eq!(fs::read_to_string(&link).unwrap(), "iso bytes");
    }

    #[tokio::test]
    async fn rebuild_removes_stale_symlinks() {
        let rt = tempfile::tempdir().unwrap();
        let source = tempfile::tempdir().unwrap();
        let old_iso = source.path().join("old.iso");
        let new_iso = source.path().join("new.iso");
        fs::write(&old_iso, b"old").unwrap();
        fs::write(&new_iso, b"new").unwrap();

        let tree = ServeTree::new(rt.path().to_path_buf());
        tree.rebuild(std::slice::from_ref(&old_iso)).await.unwrap();
        assert!(rt.path().join("isos").join("old.iso").exists());

        // Second run with a different ISO list -- the stale entry from
        // the previous run must be gone, not left dangling.
        tree.rebuild(std::slice::from_ref(&new_iso)).await.unwrap();

        assert!(!rt.path().join("isos").join("old.iso").exists());
        assert!(rt.path().join("isos").join("new.iso").exists());
    }

    #[tokio::test]
    async fn merges_isos_from_different_source_directories() {
        let rt = tempfile::tempdir().unwrap();
        let a = tempfile::tempdir().unwrap();
        let b = tempfile::tempdir().unwrap();
        let iso_a = a.path().join("alpha.iso");
        let iso_b = b.path().join("beta.iso");
        fs::write(&iso_a, b"a").unwrap();
        fs::write(&iso_b, b"b").unwrap();

        let tree = ServeTree::new(rt.path().to_path_buf());
        tree.rebuild(&[iso_a.clone(), iso_b.clone()]).await.unwrap();

        assert_eq!(
            fs::read_link(rt.path().join("isos").join("alpha.iso")).unwrap(),
            iso_a
        );
        assert_eq!(
            fs::read_link(rt.path().join("isos").join("beta.iso")).unwrap(),
            iso_b
        );
    }

    #[tokio::test]
    async fn handles_an_iso_path_that_is_itself_a_symlink() {
        // The real `nixIsos` shape: `pkgs.linkFarm` populates the source
        // directory entirely with symlinks, so `IsoDiscovery` hands
        // `ServeTree::rebuild` a symlink path, not a plain file path.
        let rt = tempfile::tempdir().unwrap();
        let target_dir = tempfile::tempdir().unwrap();
        let real_iso = target_dir.path().join("real-target.iso");
        fs::write(&real_iso, b"real bytes").unwrap();

        let farm_dir = tempfile::tempdir().unwrap();
        let symlinked_iso = farm_dir.path().join("linked.iso");
        std::os::unix::fs::symlink(&real_iso, &symlinked_iso).unwrap();

        let tree = ServeTree::new(rt.path().to_path_buf());
        tree.rebuild(std::slice::from_ref(&symlinked_iso)).await.unwrap();

        let link = rt.path().join("isos").join("linked.iso");
        // The serve-tree symlink points at the farm's symlink (not
        // resolved further) -- but must still transparently resolve all
        // the way through to the real bytes when read.
        assert_eq!(fs::read_link(&link).unwrap(), symlinked_iso);
        assert_eq!(fs::read_to_string(&link).unwrap(), "real bytes");
    }

    #[tokio::test]
    async fn a_failed_rebuild_leaves_the_previous_tree_completely_intact() {
        let rt = tempfile::tempdir().unwrap();
        let a = tempfile::tempdir().unwrap();
        let b = tempfile::tempdir().unwrap();
        let keep_iso = a.path().join("keep.iso");
        fs::write(&keep_iso, b"keep me").unwrap();

        let tree = ServeTree::new(rt.path().to_path_buf());
        tree.rebuild(std::slice::from_ref(&keep_iso)).await.unwrap();
        let keep_link = rt.path().join("isos").join("keep.iso");
        assert!(keep_link.exists());

        // Force a mid-build failure: two different source paths that
        // resolve to the SAME basename make the second `symlink()` call
        // for "collide.iso" fail with EEXIST, deterministically
        // reproducing a crash/error partway through populating the new
        // tree -- without needing real fault injection.
        let collide_1 = a.path().join("collide.iso");
        let collide_2 = b.path().join("collide.iso");
        fs::write(&collide_1, b"1").unwrap();
        fs::write(&collide_2, b"2").unwrap();

        let result = tree
            .rebuild(&[collide_1.clone(), collide_2.clone()])
            .await;
        assert!(result.is_err());

        // The previous tree must be entirely untouched -- same symlink,
        // same target, not wiped out by the failed rebuild attempt.
        assert_eq!(fs::read_link(&keep_link).unwrap(), keep_iso);
        assert_eq!(fs::read_to_string(&keep_link).unwrap(), "keep me");
        // And the failed attempt's entries must NOT have leaked into the
        // live tree either.
        assert!(!rt.path().join("isos").join("collide.iso").exists());
    }
}
