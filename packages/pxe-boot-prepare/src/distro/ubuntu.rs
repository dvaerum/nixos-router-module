use crate::config::{AutoinstallScript, BootInfo, DistroType, IsoInfo};
use crate::distro::detector::DistroDetector;
use crate::error::Result;
use crate::iso::find_file;
use async_trait::async_trait;
use std::path::Path;

pub struct UbuntuDetector;

impl UbuntuDetector {
    pub fn new() -> Self {
        Self
    }
}

#[async_trait]
impl DistroDetector for UbuntuDetector {
    fn id(&self) -> &str {
        "ubuntu"
    }

    fn priority(&self) -> u8 {
        55
    }

    async fn can_handle(&self, mount_path: &Path) -> Result<bool> {
        // Check for ubuntu-server-minimal.squashfs
        let squashfs = mount_path.join("casper/ubuntu-server-minimal.squashfs");
        Ok(squashfs.exists())
    }

    async fn extract_boot_info(&self, iso_info: &IsoInfo) -> Result<BootInfo> {
        let mount = &iso_info.mount_path;

        // Find kernel in casper directory
        let kernel = find_file(mount, &["casper/vmlinuz"]).await?;

        // Find initrd in casper directory
        let initrd = find_file(mount, &["casper/initrd"]).await?;

        Ok(BootInfo {
            kernel_path: kernel,
            initrd_path: initrd,
            distro_type: DistroType::Ubuntu,
            version: None,
            architecture: Some("amd64".to_string()),
        })
    }

    fn generate_boot_params(
        &self,
        iso_url: &str,
        _mounted_url: &str,
        _autoinstall: Option<&AutoinstallScript>,
    ) -> Vec<String> {
        vec![
            "ip=dhcp".to_string(),
            format!("url={}", iso_url),
        ]
    }
}
