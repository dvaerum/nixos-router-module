use crate::config::{AutoinstallScript, BootInfo, DistroType, IsoInfo};
use crate::distro::detector::DistroDetector;
use crate::error::Result;
use crate::iso::find_file;
use async_trait::async_trait;
use std::path::Path;

pub struct NixOsDetector;

impl NixOsDetector {
    pub fn new() -> Self {
        Self
    }
}

#[async_trait]
impl DistroDetector for NixOsDetector {
    fn id(&self) -> &str {
        "nixos"
    }

    fn priority(&self) -> u8 {
        60
    }

    async fn can_handle(&self, mount_path: &Path) -> Result<bool> {
        // Check for nix-store.squashfs
        let squashfs = mount_path.join("nix-store.squashfs");
        Ok(squashfs.exists())
    }

    async fn extract_boot_info(&self, iso_info: &IsoInfo) -> Result<BootInfo> {
        let mount = &iso_info.mount_path;

        // Find kernel (bzImage or Image inside nix store)
        // find_file now only returns actual files, not directories
        let kernel = find_file(mount, &["bzImage", "Image"]).await?;

        // Find initrd file (not directory) - search for any file with "initrd" in the name
        let initrd = find_file(mount, &["initrd", "initramfs"]).await?;

        Ok(BootInfo {
            kernel_path: kernel,
            initrd_path: initrd,
            distro_type: DistroType::NixOS,
            version: None,
            architecture: Some("x86_64".to_string()),
        })
    }

    fn generate_boot_params(
        &self,
        iso_url: &str,
        _mounted_url: &str,
        _autoinstall: Option<&AutoinstallScript>,
    ) -> Vec<String> {
        // For PXE boot, we load kernel/initrd directly from mounted ISO
        // The initrd downloads the full ISO to continue booting via findiso parameter
        // NOTE: This requires the ISO to be built with enableNetworkDownload = true
        vec![
            format!("findiso={}", iso_url),
            // NOTE: Removed hardcoded root=LABEL - findiso should be sufficient
            // The initrd will download and mount the ISO automatically
            "boot.shell_on_fail".to_string(),
            "nohibernate".to_string(),
            // Increase loglevel to debug boot issues
            "loglevel=7".to_string(),
            "lsm=landlock,yama,bpf".to_string(),
        ]
    }
}
