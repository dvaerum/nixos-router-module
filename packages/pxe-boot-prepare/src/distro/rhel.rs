use crate::config::{AutoinstallScript, BootInfo, DistroType, IsoInfo};
use crate::distro::detector::DistroDetector;
use crate::error::Result;
use crate::iso::find_file;
use async_trait::async_trait;
use std::path::Path;

pub struct RhelDetector;

impl RhelDetector {
    pub fn new() -> Self {
        Self
    }
}

#[async_trait]
impl DistroDetector for RhelDetector {
    fn id(&self) -> &str {
        "rhel"
    }

    fn priority(&self) -> u8 {
        50
    }

    async fn can_handle(&self, mount_path: &Path) -> Result<bool> {
        // Check for RPM-GPG-KEY-redhat-release
        let key_file = mount_path.join("RPM-GPG-KEY-redhat-release");
        Ok(key_file.exists())
    }

    async fn extract_boot_info(&self, iso_info: &IsoInfo) -> Result<BootInfo> {
        let mount = &iso_info.mount_path;

        // Find kernel in images/pxeboot
        let kernel = find_file(mount, &["images/pxeboot/vmlinuz"]).await?;

        // Find initrd in images/pxeboot
        let initrd = find_file(mount, &["images/pxeboot/initrd.img"]).await?;

        Ok(BootInfo {
            kernel_path: kernel,
            initrd_path: initrd,
            distro_type: DistroType::RedHat,
            version: None,
            architecture: Some("x86_64".to_string()),
        })
    }

    fn generate_boot_params(
        &self,
        _iso_url: &str,
        mounted_url: &str,
        autoinstall: Option<&AutoinstallScript>,
    ) -> Vec<String> {
        let mut params = vec![
            "initrd=initrd.img".to_string(),
            format!("inst.repo={}", mounted_url),
        ];

        // Add kickstart if provided
        if autoinstall.is_some() {
            // The script URL will be provided by the caller
            // This is a placeholder that should be replaced
            params.push("inst.ks={autoinstall_url}".to_string());
        }

        params
    }
}
