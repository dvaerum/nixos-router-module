use crate::config::{AutoinstallScript, BootInfo, IsoInfo};
use crate::error::{PxeBootError, Result};
use async_trait::async_trait;
use std::path::Path;

/// Trait for distribution detection and boot configuration
#[async_trait]
pub trait DistroDetector: Send + Sync {
    /// Unique identifier for this detector
    fn id(&self) -> &str;

    /// Priority (higher = checked first)
    fn priority(&self) -> u8 {
        50
    }

    /// Check if this detector can handle the mounted ISO
    async fn can_handle(&self, mount_path: &Path) -> Result<bool>;

    /// Extract boot information from the ISO
    async fn extract_boot_info(&self, iso_info: &IsoInfo) -> Result<BootInfo>;

    /// Generate boot parameters for this distribution
    fn generate_boot_params(
        &self,
        iso_url: &str,
        mounted_url: &str,
        autoinstall: Option<&AutoinstallScript>,
    ) -> Vec<String>;

    /// Optional: Custom GRUB entry template
    fn grub_template(&self) -> Option<String> {
        None
    }
}

/// Registry for distribution detectors
pub struct DetectorRegistry {
    detectors: Vec<Box<dyn DistroDetector>>,
}

impl DetectorRegistry {
    pub fn new() -> Self {
        let mut registry = Self {
            detectors: Vec::new(),
        };

        // Register built-in detectors
        registry.register(Box::new(super::nixos::NixOsDetector::new()));
        registry.register(Box::new(super::ubuntu::UbuntuDetector::new()));
        registry.register(Box::new(super::rhel::RhelDetector::new()));

        registry
    }

    pub fn register(&mut self, detector: Box<dyn DistroDetector>) {
        self.detectors.push(detector);
        // Sort by priority (descending)
        self.detectors
            .sort_by(|a, b| b.priority().cmp(&a.priority()));
    }

    pub async fn detect(&self, mount_path: &Path) -> Result<&dyn DistroDetector> {
        for detector in &self.detectors {
            if detector.can_handle(mount_path).await? {
                return Ok(detector.as_ref());
            }
        }

        Err(PxeBootError::DetectionFailed {
            iso: mount_path.display().to_string(),
            reason: "No detector matched".to_string(),
        })
    }
}

impl Default for DetectorRegistry {
    fn default() -> Self {
        Self::new()
    }
}
