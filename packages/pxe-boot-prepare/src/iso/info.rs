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

            let path_str = path.to_string_lossy().to_lowercase();

            for pattern in &patterns {
                let pattern_lower = pattern.to_lowercase();

                // Simple pattern matching: supports wildcards
                if path_str.contains(&pattern_lower)
                    || path.file_name().map_or(false, |name| {
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
