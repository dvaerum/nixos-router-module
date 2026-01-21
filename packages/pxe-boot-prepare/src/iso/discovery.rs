use crate::error::Result;
use std::path::PathBuf;
use walkdir::WalkDir;

pub struct IsoDiscovery {
    iso_folder: PathBuf,
}

impl IsoDiscovery {
    pub fn new(iso_folder: PathBuf) -> Self {
        Self { iso_folder }
    }

    /// Discover all ISO files in the configured directory
    pub async fn discover(&self) -> Result<Vec<PathBuf>> {
        let iso_folder = self.iso_folder.clone();

        // Run blocking walkdir in a spawn_blocking task
        let isos = tokio::task::spawn_blocking(move || {
            let mut isos = Vec::new();

            for entry in WalkDir::new(&iso_folder)
                .max_depth(1) // Don't recurse
                .into_iter()
                .filter_map(|e| e.ok())
            {
                if let Some(ext) = entry.path().extension() {
                    if ext.eq_ignore_ascii_case("iso") {
                        isos.push(entry.path().to_path_buf());
                    }
                }
            }

            // Sort for deterministic ordering
            isos.sort();
            isos
        })
        .await
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;

        Ok(isos)
    }
}
