use crate::error::{PxeBootError, Result};
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

/// Find a file in a directory tree matching a pattern
/// Only returns actual files, not directories
pub async fn find_file(base: &Path, patterns: &[&str]) -> Result<PathBuf> {
    let base = base.to_path_buf();
    let patterns: Vec<String> = patterns.iter().map(|s| s.to_string()).collect();

    tokio::task::spawn_blocking(move || {
        for entry in WalkDir::new(&base).into_iter().filter_map(|e| e.ok()) {
            let path = entry.path();

            // Skip directories - only return actual files
            if !path.is_file() {
                continue;
            }

            let relative = path.strip_prefix(&base).unwrap_or(path);
            let relative_str = relative.to_string_lossy().to_lowercase();

            for pattern in &patterns {
                let pattern_lower = pattern.to_lowercase();

                // Exact relative-path match -- NOT a substring match.
                // The prior `path_str.contains(&pattern_lower)` check
                // matched "casper/vmlinuz" against "casper/vmlinuz.efi"
                // too, silently returning whichever file readdir visited
                // first instead of the one actually asked for.
                if relative_str == pattern_lower
                    || path.file_name().is_some_and(|name| {
                        name.to_string_lossy().to_lowercase() == pattern_lower
                    })
                {
                    return Ok(path.to_path_buf());
                }
            }
        }

        Err(PxeBootError::FileNotFound(base.clone()))
    })
    .await
    .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[tokio::test]
    async fn finds_exact_relative_path_match() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("casper")).unwrap();
        fs::write(dir.path().join("casper/vmlinuz"), b"fake").unwrap();
        fs::write(dir.path().join("casper/vmlinuz.efi"), b"fake-efi").unwrap();

        let result = find_file(dir.path(), &["casper/vmlinuz"]).await.unwrap();
        assert_eq!(result, dir.path().join("casper/vmlinuz"));
    }

    #[tokio::test]
    async fn does_not_match_a_longer_filename_as_a_substring() {
        // Regression: "casper/vmlinuz" must NOT match "casper/vmlinuz.efi"
        // -- the prior substring-based check treated any path containing
        // the pattern as a hit, so a distro's own ".efi" kernel variant
        // could silently win over (or instead of) the exact "vmlinuz"
        // file the pattern was actually asking for.
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("casper")).unwrap();
        fs::write(dir.path().join("casper/vmlinuz.efi"), b"fake").unwrap();

        let result = find_file(dir.path(), &["casper/vmlinuz"]).await;
        assert!(
            result.is_err(),
            "must not match vmlinuz.efi for pattern casper/vmlinuz, got {result:?}"
        );
    }

    #[tokio::test]
    async fn finds_by_bare_filename_fallback() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("vmlinuz"), b"fake").unwrap();

        let result = find_file(dir.path(), &["vmlinuz"]).await.unwrap();
        assert_eq!(result, dir.path().join("vmlinuz"));
    }

    #[tokio::test]
    async fn errors_when_no_pattern_matches() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("readme.txt"), b"fake").unwrap();

        let result = find_file(dir.path(), &["casper/vmlinuz"]).await;
        assert!(result.is_err());
    }
}
