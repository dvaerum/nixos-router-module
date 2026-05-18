use crate::config::PxeBootConfig;
use crate::error::Result;
use std::path::PathBuf;

pub struct AutoinstallManager {
    runtime_root: PathBuf,
}

impl AutoinstallManager {
    pub fn new(runtime_root: PathBuf) -> Self {
        Self { runtime_root }
    }

    /// Prepare autoinstall scripts by copying them to the runtime directory
    pub async fn prepare(&self, config: &PxeBootConfig) -> Result<()> {
        let autoinstall_root = self.runtime_root.join("unattented-install");

        for (iso_name, scripts) in &config.autoinstall {
            let iso_script_dir = autoinstall_root.join(iso_name);
            tokio::fs::create_dir_all(&iso_script_dir).await?;

            for script in scripts {
                let dest = iso_script_dir.join(&script.name);
                tracing::debug!(
                    "Copying autoinstall script: {} -> {}",
                    script.script_path.display(),
                    dest.display()
                );
                // tokio::fs::copy preserves the source mode. The source is a
                // /nix/store file (0444), so a prior run's destination is also
                // 0444 — which the next overwrite cannot open for writing
                // because this service runs without CAP_DAC_OVERRIDE. Remove
                // the destination first so the copy is a fresh create.
                // Removing a file is checked against the parent directory's
                // permissions (which is writable), not the file's mode bits.
                match tokio::fs::remove_file(&dest).await {
                    Ok(()) => {}
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                    Err(e) => return Err(e.into()),
                }
                tokio::fs::copy(&script.script_path, dest).await?;
            }
        }

        tracing::info!("Prepared autoinstall scripts");
        Ok(())
    }
}
