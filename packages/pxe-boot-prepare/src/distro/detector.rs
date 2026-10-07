use crate::config::{AutoinstallScript, BootInfo, IsoInfo};
use crate::error::{PxeBootError, Result};
use async_trait::async_trait;
use std::path::Path;

/// Kernel-param placeholder for the autoinstall seed *file* URL (e.g.
/// RHEL's `inst.ks=`). Substituted by `MenuEntryFactory::create_entry`;
/// kept as a single shared constant so the producer side (each
/// `DistroDetector::generate_boot_params` impl) and the consumer side
/// (`MenuEntryFactory`) can never drift apart by retyping the literal.
pub const AUTOINSTALL_URL_PLACEHOLDER: &str = "{autoinstall_url}";

/// Kernel-param placeholder for the autoinstall seed *directory* URL,
/// ending in `/` (e.g. Ubuntu NoCloud's `ds=nocloud-net;s=`). See
/// `AUTOINSTALL_URL_PLACEHOLDER` above.
pub const AUTOINSTALL_DIR_URL_PLACEHOLDER: &str = "{autoinstall_dir_url}";

/// Trait for distribution detection and boot configuration
#[async_trait]
pub trait DistroDetector: Send + Sync {
    /// Unique identifier for this detector
    fn id(&self) -> &str;

    /// Priority (higher = checked first). No default on purpose: a
    /// detector that silently inherited a shared default would create an
    /// invisible tie with any other detector relying on the same
    /// default, whose winner then depends purely on registration order
    /// -- forcing every detector to state its own priority turns that
    /// into a compile-time-visible decision instead.
    fn priority(&self) -> u8;

    /// Check if this detector can handle the mounted ISO
    async fn can_handle(&self, mount_path: &Path) -> Result<bool>;

    /// Extract boot information from the ISO
    async fn extract_boot_info(&self, iso_info: &IsoInfo) -> Result<BootInfo>;

    /// Generate boot parameters for this distribution
    fn generate_boot_params(
        &self,
        iso_url: &str,
        mounted_url: &str,
        boot_info: &BootInfo,
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
        // Lowest priority (0): always matches, so it only ever gets
        // reached once every real detector has declined -- gives the
        // registry a concrete "we tried, nothing matched" outcome instead
        // of a generic registry-level error.
        registry.register(Box::new(super::unknown::UnknownDetector::new()));

        registry
    }

    pub fn register(&mut self, detector: Box<dyn DistroDetector>) {
        // Removing the trait's default priority (see above) prevents
        // ACCIDENTAL collisions from a forgotten override, but two
        // detectors can still deliberately declare the same priority --
        // surface that loudly instead of letting registration order
        // silently decide the winner with no trace in the logs.
        if let Some(existing) = self
            .detectors
            .iter()
            .find(|d| d.priority() == detector.priority())
        {
            tracing::warn!(
                "Detector '{}' has the same priority ({}) as already-registered \
                 detector '{}' -- tie-break falls back to registration order, \
                 which is almost certainly not what either detector intended",
                detector.id(),
                detector.priority(),
                existing.id(),
            );
        }

        self.detectors.push(detector);
        // Sort by priority (descending)
        self.detectors
            .sort_by_key(|d| std::cmp::Reverse(d.priority()));
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

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn detect_falls_through_to_unknown_detector_when_nothing_else_matches() {
        let dir = tempfile::tempdir().unwrap();
        // No nix-store.squashfs, no casper/, no images/pxeboot/ -- nothing
        // any real detector recognizes.
        let registry = DetectorRegistry::new();

        let detector = registry.detect(dir.path()).await.unwrap();

        assert_eq!(detector.id(), "unknown");
    }

    struct FakeDetector {
        id: &'static str,
        priority: u8,
    }

    #[async_trait]
    impl DistroDetector for FakeDetector {
        fn id(&self) -> &str {
            self.id
        }

        fn priority(&self) -> u8 {
            self.priority
        }

        async fn can_handle(&self, _mount_path: &Path) -> Result<bool> {
            Ok(true)
        }

        async fn extract_boot_info(&self, _iso_info: &IsoInfo) -> Result<BootInfo> {
            unimplemented!("not exercised by the tie-break test")
        }

        fn generate_boot_params(
            &self,
            _iso_url: &str,
            _mounted_url: &str,
            _boot_info: &BootInfo,
            _autoinstall: Option<&AutoinstallScript>,
        ) -> Vec<String> {
            Vec::new()
        }
    }

    #[tokio::test]
    async fn equal_priority_ties_are_broken_by_registration_order() {
        // `register`'s `sort_by` is a stable sort (Rust's slice sort is
        // documented stable) -- two detectors at the SAME priority must
        // keep their relative registration order rather than the tie
        // being an accidental, unspecified artifact of sort
        // implementation details.
        let mut registry = DetectorRegistry {
            detectors: Vec::new(),
        };
        registry.register(Box::new(FakeDetector {
            id: "first",
            priority: 42,
        }));
        registry.register(Box::new(FakeDetector {
            id: "second",
            priority: 42,
        }));

        let dir = tempfile::tempdir().unwrap();
        let detector = registry.detect(dir.path()).await.unwrap();

        assert_eq!(detector.id(), "first");
    }
}
