use crate::config::{AutoinstallScript, BootInfo, DistroType, IsoInfo};
use crate::distro::arch::detect_architecture_from_file_name;
use crate::distro::detector::{DistroDetector, AUTOINSTALL_URL_PLACEHOLDER};
use crate::error::Result;
use crate::iso::find_file;
use async_trait::async_trait;
use std::path::Path;

pub struct RhelDetector;

impl Default for RhelDetector {
    fn default() -> Self {
        Self::new()
    }
}

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
            architecture: detect_architecture_from_file_name(&iso_info.file_name),
            init_path: None,
        })
    }

    fn generate_boot_params(
        &self,
        _iso_url: &str,
        mounted_url: &str,
        _boot_info: &BootInfo,
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
            params.push(format!("inst.ks={AUTOINSTALL_URL_PLACEHOLDER}"));
        }

        params
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;

    fn script() -> AutoinstallScript {
        AutoinstallScript {
            name: "ks.cfg".to_string(),
            script_path: PathBuf::from("/nix/store/xxx-ks.cfg"),
        }
    }

    fn boot_info() -> BootInfo {
        BootInfo {
            kernel_path: PathBuf::from("/mnt/images/pxeboot/vmlinuz"),
            initrd_path: PathBuf::from("/mnt/images/pxeboot/initrd.img"),
            distro_type: DistroType::RedHat,
            version: None,
            architecture: Some("x86_64".to_string()),
            init_path: None,
        }
    }

    #[test]
    fn boots_with_initrd_and_inst_repo() {
        let d = RhelDetector::new();
        let params = d.generate_boot_params(
            "http://gw:1338/rhel.iso",
            "http://gw:1337/iso-mountpoint/rhel.iso",
            &boot_info(),
            None,
        );
        assert!(params.contains(&"initrd=initrd.img".to_string()));
        assert!(params.contains(&"inst.repo=http://gw:1337/iso-mountpoint/rhel.iso".to_string()));
    }

    #[test]
    fn inst_repo_uses_mounted_url_not_iso_url() {
        // RHEL's installer reads its repo tree directly from the
        // loop-mounted ISO (`mounted_url`), unlike Ubuntu/casper which
        // downloads the whole ISO image (`iso_url`) -- regression test
        // for accidentally swapping which URL feeds which param.
        let d = RhelDetector::new();
        let params = d.generate_boot_params(
            "http://gw:1338/rhel.iso",
            "http://gw:1337/iso-mountpoint/rhel.iso",
            &boot_info(),
            None,
        );
        assert!(!params.iter().any(|p| p.contains("1338")));
    }

    #[test]
    fn adds_kickstart_placeholder_when_script_present() {
        let d = RhelDetector::new();
        let s = script();
        let params = d.generate_boot_params(
            "http://gw:1338/rhel.iso",
            "http://gw:1337/iso-mountpoint/rhel.iso",
            &boot_info(),
            Some(&s),
        );
        // The actual URL is substituted later by MenuEntryFactory.
        assert!(params.contains(&format!("inst.ks={AUTOINSTALL_URL_PLACEHOLDER}")));
    }

    #[test]
    fn no_kickstart_arg_when_script_absent() {
        let d = RhelDetector::new();
        let params = d.generate_boot_params(
            "http://gw:1338/rhel.iso",
            "http://gw:1337/iso-mountpoint/rhel.iso",
            &boot_info(),
            None,
        );
        assert!(!params.iter().any(|p| p.starts_with("inst.ks=")));
    }

    #[tokio::test]
    async fn can_handle_detects_redhat_gpg_key() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("RPM-GPG-KEY-redhat-release"), b"fake").unwrap();

        let d = RhelDetector::new();
        assert!(d.can_handle(dir.path()).await.unwrap());
    }

    #[tokio::test]
    async fn can_handle_rejects_missing_gpg_key() {
        let dir = tempfile::tempdir().unwrap();

        let d = RhelDetector::new();
        assert!(!d.can_handle(dir.path()).await.unwrap());
    }

    #[tokio::test]
    async fn extract_boot_info_finds_pxeboot_kernel_and_initrd() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("images/pxeboot")).unwrap();
        fs::write(dir.path().join("images/pxeboot/vmlinuz"), b"fake-kernel").unwrap();
        fs::write(
            dir.path().join("images/pxeboot/initrd.img"),
            b"fake-initrd",
        )
        .unwrap();

        let iso_info = IsoInfo {
            file_name: "rhel-9.6-x86_64-dvd.iso".to_string(),
            file_path: dir.path().join("rhel-9.6-x86_64-dvd.iso"),
            mount_path: dir.path().to_path_buf(),
            distro_type: DistroType::RedHat,
            kernel_path: PathBuf::new(),
            initrd_path: PathBuf::new(),
        };

        let d = RhelDetector::new();
        let boot_info = d.extract_boot_info(&iso_info).await.unwrap();

        assert_eq!(
            boot_info.kernel_path,
            dir.path().join("images/pxeboot/vmlinuz")
        );
        assert_eq!(
            boot_info.initrd_path,
            dir.path().join("images/pxeboot/initrd.img")
        );
        assert_eq!(boot_info.distro_type, DistroType::RedHat);
        assert_eq!(boot_info.architecture.as_deref(), Some("x86_64"));
    }

    #[tokio::test]
    async fn extract_boot_info_detects_aarch64_from_file_name() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("images/pxeboot")).unwrap();
        fs::write(dir.path().join("images/pxeboot/vmlinuz"), b"fake-kernel").unwrap();
        fs::write(
            dir.path().join("images/pxeboot/initrd.img"),
            b"fake-initrd",
        )
        .unwrap();

        let iso_info = IsoInfo {
            file_name: "rhel-9.6-aarch64-dvd.iso".to_string(),
            file_path: dir.path().join("rhel-9.6-aarch64-dvd.iso"),
            mount_path: dir.path().to_path_buf(),
            distro_type: DistroType::RedHat,
            kernel_path: PathBuf::new(),
            initrd_path: PathBuf::new(),
        };

        let d = RhelDetector::new();
        let boot_info = d.extract_boot_info(&iso_info).await.unwrap();

        assert_eq!(boot_info.architecture.as_deref(), Some("aarch64"));
    }

    #[tokio::test]
    async fn extract_boot_info_architecture_is_none_without_a_recognizable_marker() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("images/pxeboot")).unwrap();
        fs::write(dir.path().join("images/pxeboot/vmlinuz"), b"fake-kernel").unwrap();
        fs::write(
            dir.path().join("images/pxeboot/initrd.img"),
            b"fake-initrd",
        )
        .unwrap();

        let iso_info = IsoInfo {
            file_name: "mystery-rhel-clone.iso".to_string(),
            file_path: dir.path().join("mystery-rhel-clone.iso"),
            mount_path: dir.path().to_path_buf(),
            distro_type: DistroType::RedHat,
            kernel_path: PathBuf::new(),
            initrd_path: PathBuf::new(),
        };

        let d = RhelDetector::new();
        let boot_info = d.extract_boot_info(&iso_info).await.unwrap();

        assert_eq!(boot_info.architecture, None);
    }
}
