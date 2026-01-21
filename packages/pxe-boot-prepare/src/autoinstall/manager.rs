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
                tokio::fs::copy(&script.script_path, dest).await?;
            }
        }

        tracing::info!("Prepared autoinstall scripts");
        Ok(())
    }
}
