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

        push_kickstart(&mut params, autoinstall);
        params
    }

    /// Only for an ISO that carries the installer image: over NFS the
    /// installer mounts the exported tree as its repo and loop-mounts
    /// `images/install.img` from it, so without that file there is nothing to
    /// boot from.
    fn supports_nfs(&self, iso_info: &IsoInfo) -> bool {
        iso_info.mount_path.join("images/install.img").exists()
    }

    /// `inst.repo=nfs:<server>:<path>` makes the installer (anaconda's dracut
    /// hooks, checked against the real RHEL 9.6 and 10.2 initrds) mount that
    /// export as its repo and find `images/install.img` and the packages in
    /// it, instead of downloading the installer image into RAM over HTTP. With
    /// no `nfsvers=` it defaults to NFS version 3, which the router serves.
    ///
    /// The path gets a trailing slash. The same hook treats an `nfs:` repo that
    /// ends in `.iso` as an ISO *file* and mounts its parent directory to look
    /// for it, and an ISO's mount point is a directory named after the file
    /// (`.../rhel-10.2-x86_64-dvd.iso`): without the slash the installer asked
    /// for the parent, which is not exported (seen on real hardware).
    fn generate_nfs_boot_params(
        &self,
        nfs_root: &str,
        _boot_info: &BootInfo,
        autoinstall: Option<&AutoinstallScript>,
    ) -> Option<Vec<String>> {
        let mut params = vec![
            "initrd=initrd.img".to_string(),
            format!("inst.repo=nfs:{}/", nfs_root.trim_end_matches('/')),
        ];
        push_kickstart(&mut params, autoinstall);
        Some(params)
    }
}

/// The kickstart (unattended install) stays an HTTP fetch in both modes. The
/// script URL is substituted by the caller for the placeholder.
fn push_kickstart(params: &mut Vec<String>, autoinstall: Option<&AutoinstallScript>) {
    if autoinstall.is_some() {
        params.push(format!("inst.ks={AUTOINSTALL_URL_PLACEHOLDER}"));
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

    fn rhel_iso(with_install_img: bool) -> (tempfile::TempDir, IsoInfo) {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("images/pxeboot")).unwrap();
        fs::write(dir.path().join("RPM-GPG-KEY-redhat-release"), b"key").unwrap();
        if with_install_img {
            fs::write(dir.path().join("images/install.img"), b"stage2").unwrap();
        }
        let iso = IsoInfo::placeholder(
            "rhel-9.6-x86_64-dvd.iso".into(),
            PathBuf::from("/x/rhel-9.6-x86_64-dvd.iso"),
            dir.path().to_path_buf(),
        );
        (dir, iso)
    }

    #[test]
    fn nfs_boot_mounts_the_isos_tree_as_the_installer_repo() {
        let params = RhelDetector::new()
            .generate_nfs_boot_params(
                "192.0.2.1:/run/pxe-boot/iso-mountpoint/rhel.iso",
                &boot_info(),
                None,
            )
            .unwrap();
        assert!(params.contains(&"initrd=initrd.img".to_string()));
        assert!(params
            .contains(&"inst.repo=nfs:192.0.2.1:/run/pxe-boot/iso-mountpoint/rhel.iso/".to_string()));
    }

    #[test]
    fn nfs_repo_path_never_ends_in_dot_iso() {
        // anaconda's dracut hook treats an nfs: repo ending in ".iso" as an ISO
        // *file* and mounts its PARENT directory to find it. The mount point of
        // an ISO is a directory named after the file, so without a trailing
        // slash the installer asks for a path that is not exported.
        let params = RhelDetector::new()
            .generate_nfs_boot_params(
                "192.0.2.1:/run/pxe-boot/iso-mountpoint/rhel-10.2-x86_64-dvd.iso",
                &boot_info(),
                None,
            )
            .unwrap();
        let repo = params
            .iter()
            .find_map(|p| p.strip_prefix("inst.repo="))
            .expect("an inst.repo= parameter");
        assert!(!repo.ends_with(".iso"), "{repo}");
    }

    #[test]
    fn nfs_boot_does_not_use_an_http_repo() {
        let params = RhelDetector::new()
            .generate_nfs_boot_params("192.0.2.1:/m/rhel.iso", &boot_info(), None)
            .unwrap();
        assert!(!params.iter().any(|p| p.contains("http://")));
    }

    #[test]
    fn nfs_boot_keeps_the_kickstart() {
        let s = script();
        let params = RhelDetector::new()
            .generate_nfs_boot_params("192.0.2.1:/m/rhel.iso", &boot_info(), Some(&s))
            .unwrap();
        assert!(params.contains(&format!("inst.ks={AUTOINSTALL_URL_PLACEHOLDER}")));
    }

    #[test]
    fn nfs_boot_without_a_kickstart_has_no_ks_param() {
        let params = RhelDetector::new()
            .generate_nfs_boot_params("192.0.2.1:/m/rhel.iso", &boot_info(), None)
            .unwrap();
        assert!(!params.iter().any(|p| p.starts_with("inst.ks=")));
    }

    #[test]
    fn nfs_is_supported_only_when_the_iso_carries_the_installer_image() {
        // The installer finds its stage2 image (images/install.img) inside the
        // NFS-mounted repo; without it there is nothing to boot from over NFS.
        let d = RhelDetector::new();
        let (_a, with) = rhel_iso(true);
        let (_b, without) = rhel_iso(false);
        assert!(d.supports_nfs(&with));
        assert!(!d.supports_nfs(&without));
    }
}
