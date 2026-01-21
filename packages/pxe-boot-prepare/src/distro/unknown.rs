use crate::config::{AutoinstallScript, BootInfo, IsoInfo};
use crate::distro::detector::DistroDetector;
use crate::error::{PxeBootError, Result};
use async_trait::async_trait;
use std::path::Path;

pub struct UnknownDetector;

impl UnknownDetector {
    pub fn new() -> Self {
        Self
    }
}

#[async_trait]
impl DistroDetector for UnknownDetector {
    fn id(&self) -> &str {
        "unknown"
    }

    fn priority(&self) -> u8 {
        0 // Lowest priority
    }

    async fn can_handle(&self, _mount_path: &Path) -> Result<bool> {
        // This detector always matches as a fallback
        Ok(true)
    }

    async fn extract_boot_info(&self, iso_info: &IsoInfo) -> Result<BootInfo> {
        Err(PxeBootError::DetectionFailed {
            iso: iso_info.file_name.clone(),
            reason: "Unknown distribution type".to_string(),
        })
    }

    fn generate_boot_params(
        &self,
        _iso_url: &str,
        _mounted_url: &str,
        _autoinstall: Option<&AutoinstallScript>,
    ) -> Vec<String> {
        vec![]
    }
}
