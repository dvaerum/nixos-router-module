use crate::error::{PxeBootError, Result};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use tokio::process::Command;

pub struct IsoMounter {
    runtime_root: PathBuf,
}

impl IsoMounter {
    pub fn new(runtime_root: PathBuf) -> Self {
        Self { runtime_root }
    }

    pub fn mount_path(&self, iso_name: &str) -> PathBuf {
        self.runtime_root.join("iso-mountpoint").join(iso_name)
    }

    /// Mount an ISO, handling existing mounts intelligently
    pub async fn mount(&self, iso_path: &Path) -> Result<PathBuf> {
        let iso_name = iso_path
            .file_name()
            .ok_or_else(|| PxeBootError::Config("Invalid ISO path".into()))?
            .to_string_lossy();

        let mount_point = self.mount_path(&iso_name);

        // Create mount point
        tokio::fs::create_dir_all(&mount_point).await?;

        // Check if already mounted
        if self.is_mounted(&mount_point).await? {
            // Verify it's the correct ISO
            if self.verify_mount(&mount_point, iso_path).await? {
                tracing::info!("ISO already correctly mounted: {}", iso_name);
                return Ok(mount_point);
            } else {
                // Wrong ISO mounted, unmount it
                tracing::warn!(
                    "Incorrect ISO mounted at {}, remounting",
                    mount_point.display()
                );
                self.unmount(&mount_point).await?;
            }
        }

        // Mount the ISO
        self.do_mount(iso_path, &mount_point).await?;

        tracing::info!(
            "Mounted ISO: {} -> {}",
            iso_name,
            mount_point.display()
        );
        Ok(mount_point)
    }

    async fn is_mounted(&self, path: &Path) -> Result<bool> {
        let output = Command::new("mountpoint")
            .arg("-q")
            .arg(path)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .await?;

        Ok(output.success())
    }

    async fn verify_mount(&self, mount_point: &Path, expected_iso: &Path) -> Result<bool> {
        // Read /proc/mounts to verify the source
        let mounts = tokio::fs::read_to_string("/proc/mounts").await?;

        for line in mounts.lines() {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2 && parts[1] == mount_point.to_string_lossy() {
                return Ok(parts[0] == expected_iso.to_string_lossy());
            }
        }

        Ok(false)
    }

    async fn do_mount(&self, iso_path: &Path, mount_point: &Path) -> Result<()> {
        let status = Command::new("mount")
            .arg("-t")
            .arg("iso9660")
            .arg("-o")
            .arg("loop,ro")
            .arg(iso_path)
            .arg(mount_point)
            .status()
            .await?;

        if !status.success() {
            return Err(PxeBootError::MountFailed {
                path: iso_path.to_path_buf(),
                reason: format!("mount command exited with {}", status),
            });
        }

        Ok(())
    }

    async fn unmount(&self, mount_point: &Path) -> Result<()> {
        Command::new("umount").arg(mount_point).status().await?;

        Ok(())
    }

    /// Unmount all ISOs (cleanup)
    pub async fn unmount_all(&self) -> Result<()> {
        let mount_root = self.runtime_root.join("iso-mountpoint");

        if !mount_root.exists() {
            return Ok(());
        }

        let mut entries = tokio::fs::read_dir(&mount_root).await?;

        while let Some(entry) = entries.next_entry().await? {
            if self.is_mounted(&entry.path()).await? {
                tracing::info!("Unmounting: {}", entry.path().display());
                self.unmount(&entry.path()).await?;
            }
        }

        Ok(())
    }
}
