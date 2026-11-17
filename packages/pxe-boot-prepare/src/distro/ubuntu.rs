use crate::config::{AutoinstallScript, BootInfo, DistroType, IsoInfo};
use crate::distro::arch::detect_architecture_from_file_name;
use crate::distro::detector::{DistroDetector, AUTOINSTALL_DIR_URL_PLACEHOLDER};
use crate::error::Result;
use crate::iso::find_file;
use async_trait::async_trait;
use std::path::Path;

pub struct UbuntuDetector;

impl Default for UbuntuDetector {
    fn default() -> Self {
        Self::new()
    }
}

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
        // Server ISOs carry a squashfs with an Ubuntu-specific name.
        if mount_path
            .join("casper/ubuntu-server-minimal.squashfs")
            .exists()
        {
            return Ok(true);
        }

        // Desktop ISOs (and flavours such as Kubuntu) have no such file, and
        // other casper distros (Linux Mint, ...) share the same layout, so
        // `.disk/info` ("Ubuntu 26.04.1 LTS ...") is what tells them apart.
        if !mount_path.join("casper/vmlinuz").exists() {
            return Ok(false);
        }
        Ok(
            match tokio::fs::read_to_string(mount_path.join(".disk/info")).await {
                Ok(info) => info.to_lowercase().contains("ubuntu"),
                // No readable `.disk/info`: not enough evidence to claim it.
                Err(_) => false,
            },
        )
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
            architecture: detect_architecture_from_file_name(&iso_info.file_name),
            init_path: None,
        })
    }

    fn generate_boot_params(
        &self,
        iso_url: &str,
        _mounted_url: &str,
        _boot_info: &BootInfo,
        autoinstall: Option<&AutoinstallScript>,
    ) -> Vec<String> {
        // Boot by downloading the whole ISO into RAM (`url=`). This is casper's
        // only supported HTTP netboot mode — `fetch=` of the layered server
        // squashfs is unsupported (casper needs the entire /casper directory as a
        // single medium), and every HTTP mode copies the filesystem fully into
        // RAM anyway. The low-memory alternative is an on-demand NFS mount
        // (`netboot=nfs`), see `generate_nfs_boot_params`; this HTTP path is
        // what runs when `pxe-boot.nfs` is off or this ISO is pinned to HTTP.
        // `BOOTIF=${net_default_mac}` scopes casper's initramfs DHCP to the
        // single interface GRUB actually PXE-booted from (matched by MAC
        // address via configure_networking()'s BOOTIF path in
        // initramfs-tools' scripts/functions). Without this, bare `ip=dhcp`
        // races DHCP across *every* NIC the machine has; on a multi-homed
        // host, if a second interface (e.g. an external/uplink NIC) answers
        // DHCP faster than the intended PXE interface, casper's oneshot
        // dhcpcd client exits on the first successful lease and the PXE
        // interface may never get configured, breaking the `url=` fetch of
        // the ISO. `net_default_mac` is a GRUB-provided variable
        // (colon-separated, e.g. "52:54:00:aa:bb:cc") that GRUB interpolates
        // into the kernel command line; casper's BOOTIF parser strips a
        // leading "01-" prefix and converts "-" to ":" before matching
        // against /sys/class/net/*/address — since our value has no "-" at
        // all, both operations are no-ops and it passes through unchanged,
        // so no manual dash-reformatting is needed here.
        let mut params = vec![
            "BOOTIF=${net_default_mac}".to_string(),
            "ip=dhcp".to_string(),
            format!("url={}", iso_url),
        ];

        push_autoinstall_params(&mut params, autoinstall);
        params
    }

    fn supports_nfs(&self, _iso_info: &IsoInfo) -> bool {
        true
    }

    /// Boots casper from the ISO's own mounted tree over NFS (`netboot=nfs`)
    /// instead of downloading the whole ISO into RAM (`url=`), which is what
    /// makes Desktop-sized images (~6 GB) unbootable on small machines.
    /// `BOOTIF`/`ip=dhcp` are the same as for `url=`, see
    /// `generate_boot_params`.
    fn generate_nfs_boot_params(
        &self,
        nfs_root: &str,
        _boot_info: &BootInfo,
        autoinstall: Option<&AutoinstallScript>,
    ) -> Option<Vec<String>> {
        let mut params = vec![
            "BOOTIF=${net_default_mac}".to_string(),
            "ip=dhcp".to_string(),
            "boot=casper".to_string(),
            "netboot=nfs".to_string(),
            format!("nfsroot={nfs_root}"),
        ];
        push_autoinstall_params(&mut params, autoinstall);
        Some(params)
    }
}

/// Ubuntu Server (subiquity) unattended install. `autoinstall` runs the
/// installer non-interactively; `ds=nocloud-net;s=<dir>/` points cloud-init
/// at the directory serving `user-data` + `meta-data`. The semicolon is
/// escaped (`\;`) so GRUB treats the whole value as one kernel argument.
/// `{autoinstall_dir_url}` (a directory URL ending in `/`) is substituted
/// by MenuEntryFactory.
fn push_autoinstall_params(params: &mut Vec<String>, autoinstall: Option<&AutoinstallScript>) {
    if autoinstall.is_some() {
        params.push("autoinstall".to_string());
        params.push(format!("ds=nocloud-net\\;s={AUTOINSTALL_DIR_URL_PLACEHOLDER}"));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;

    fn script() -> AutoinstallScript {
        AutoinstallScript {
            name: "minimal-environment.yaml".to_string(),
            script_path: PathBuf::from("/nix/store/xxx-minimal-environment.yaml"),
        }
    }

    fn boot_info() -> BootInfo {
        BootInfo {
            kernel_path: PathBuf::from("/mnt/casper/vmlinuz"),
            initrd_path: PathBuf::from("/mnt/casper/initrd"),
            distro_type: DistroType::Ubuntu,
            version: None,
            architecture: Some("amd64".to_string()),
            init_path: None,
        }
    }

    #[test]
    fn boots_from_iso_url() {
        let d = UbuntuDetector::new();
        let params = d.generate_boot_params(
            "http://gw:1338/ubuntu.iso",
            "http://gw:1337/iso-mountpoint/ubuntu.iso",
            &boot_info(),
            None,
        );
        assert!(params.contains(&"ip=dhcp".to_string()));
        assert!(params.contains(&"url=http://gw:1338/ubuntu.iso".to_string()));
    }

    #[test]
    fn scopes_dhcp_to_pxe_boot_interface_via_bootif() {
        // Regression test: bare `ip=dhcp` races DHCP across every NIC on a
        // multi-homed machine. `BOOTIF=${net_default_mac}` must be present so
        // casper's initramfs only configures the interface GRUB actually
        // PXE-booted from, and it must come from GRUB's own variable (not a
        // hardcoded interface name, which isn't portable across hosts/VMs).
        let d = UbuntuDetector::new();
        let params = d.generate_boot_params(
            "http://gw:1338/ubuntu.iso",
            "http://gw:1337/iso-mountpoint/ubuntu.iso",
            &boot_info(),
            None,
        );
        assert!(params.contains(&"BOOTIF=${net_default_mac}".to_string()));
        assert!(!params.iter().any(|p| p.contains("enp") || p.contains("eth")));
    }

    #[test]
    fn adds_autoinstall_and_nocloud_when_script_present() {
        let d = UbuntuDetector::new();
        let s = script();
        let params = d.generate_boot_params(
            "http://gw:1338/ubuntu.iso",
            "http://m",
            &boot_info(),
            Some(&s),
        );
        assert!(params.contains(&"url=http://gw:1338/ubuntu.iso".to_string()));
        assert!(params.contains(&"autoinstall".to_string()));
        // The dir-URL placeholder is substituted later by MenuEntryFactory; the
        // semicolon is escaped so GRUB keeps it as a single argument.
        assert!(params.contains(&format!("ds=nocloud-net\\;s={AUTOINSTALL_DIR_URL_PLACEHOLDER}")));
    }

    #[test]
    fn no_autoinstall_args_when_script_absent() {
        let d = UbuntuDetector::new();
        let params = d.generate_boot_params("http://i", "http://m", &boot_info(), None);
        assert!(!params.contains(&"autoinstall".to_string()));
        assert!(!params.iter().any(|p| p.starts_with("ds=")));
    }

    #[test]
    fn nfs_boot_uses_casper_netboot_nfs_with_the_given_root() {
        let d = UbuntuDetector::new();
        let params = d
            .generate_nfs_boot_params("192.0.2.1:/run/pxe-boot/iso-mountpoint/u.iso", &boot_info(), None)
            .unwrap();
        assert!(params.contains(&"boot=casper".to_string()));
        assert!(params.contains(&"netboot=nfs".to_string()));
        assert!(params
            .contains(&"nfsroot=192.0.2.1:/run/pxe-boot/iso-mountpoint/u.iso".to_string()));
    }

    #[test]
    fn nfs_boot_does_not_download_the_iso() {
        let d = UbuntuDetector::new();
        let params = d
            .generate_nfs_boot_params("192.0.2.1:/m/u.iso", &boot_info(), None)
            .unwrap();
        assert!(!params.iter().any(|p| p.starts_with("url=")));
    }

    #[test]
    fn nfs_boot_still_scopes_dhcp_to_the_pxe_interface() {
        let d = UbuntuDetector::new();
        let params = d
            .generate_nfs_boot_params("192.0.2.1:/m/u.iso", &boot_info(), None)
            .unwrap();
        assert!(params.contains(&"BOOTIF=${net_default_mac}".to_string()));
        assert!(params.contains(&"ip=dhcp".to_string()));
    }

    #[test]
    fn nfs_boot_keeps_the_autoinstall_seed() {
        let d = UbuntuDetector::new();
        let s = script();
        let params = d
            .generate_nfs_boot_params("192.0.2.1:/m/u.iso", &boot_info(), Some(&s))
            .unwrap();
        assert!(params.contains(&"autoinstall".to_string()));
        assert!(params.contains(&format!("ds=nocloud-net\\;s={AUTOINSTALL_DIR_URL_PLACEHOLDER}")));
    }

    #[test]
    fn supports_nfs_agrees_with_the_nfs_params() {
        let d = UbuntuDetector::new();
        let iso = IsoInfo::placeholder("u.iso".into(), PathBuf::from("/x/u.iso"), PathBuf::from("/m/u.iso"));
        assert!(d.supports_nfs(&iso));
        assert!(d.generate_nfs_boot_params("h:/p", &boot_info(), None).is_some());
    }

    #[tokio::test]
    async fn can_handle_detects_casper_squashfs() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("casper")).unwrap();
        fs::write(
            dir.path().join("casper/ubuntu-server-minimal.squashfs"),
            b"fake",
        )
        .unwrap();

        let d = UbuntuDetector::new();
        assert!(d.can_handle(dir.path()).await.unwrap());
    }

    #[tokio::test]
    async fn can_handle_rejects_missing_squashfs() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("casper")).unwrap();

        let d = UbuntuDetector::new();
        assert!(!d.can_handle(dir.path()).await.unwrap());
    }

    /// Lays out a casper ISO the way the desktop image does: no
    /// `ubuntu-server-minimal.squashfs`, just `minimal*.squashfs` and a
    /// `.disk/info` naming the distro.
    fn desktop_iso(disk_info: Option<&str>) -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("casper")).unwrap();
        fs::write(dir.path().join("casper/vmlinuz"), b"fake-kernel").unwrap();
        fs::write(dir.path().join("casper/initrd"), b"fake-initrd").unwrap();
        fs::write(dir.path().join("casper/minimal.squashfs"), b"fake").unwrap();
        if let Some(info) = disk_info {
            fs::create_dir_all(dir.path().join(".disk")).unwrap();
            fs::write(dir.path().join(".disk/info"), info).unwrap();
        }
        dir
    }

    #[tokio::test]
    async fn can_handle_detects_desktop_iso_by_disk_info() {
        let dir = desktop_iso(Some(
            "Ubuntu 26.04.1 LTS \"Resolute Raccoon\" - Release amd64 (20260826)\n",
        ));
        let d = UbuntuDetector::new();
        assert!(d.can_handle(dir.path()).await.unwrap());
    }

    #[tokio::test]
    async fn can_handle_detects_ubuntu_flavours() {
        let dir = desktop_iso(Some("Kubuntu 26.04 LTS - Release amd64\n"));
        let d = UbuntuDetector::new();
        assert!(d.can_handle(dir.path()).await.unwrap());
    }

    #[tokio::test]
    async fn can_handle_rejects_other_casper_distros() {
        // Linux Mint and friends ship the same casper layout but are not
        // Ubuntu; claiming them would hand them Ubuntu's boot parameters.
        let dir = desktop_iso(Some("Linux Mint 22 \"Wilma\" - Release amd64\n"));
        let d = UbuntuDetector::new();
        assert!(!d.can_handle(dir.path()).await.unwrap());
    }

    #[tokio::test]
    async fn can_handle_rejects_casper_iso_without_disk_info() {
        let dir = desktop_iso(None);
        let d = UbuntuDetector::new();
        assert!(!d.can_handle(dir.path()).await.unwrap());
    }

    #[tokio::test]
    async fn can_handle_rejects_ubuntu_disk_info_without_casper_kernel() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join(".disk")).unwrap();
        fs::write(dir.path().join(".disk/info"), "Ubuntu 26.04.1 LTS\n").unwrap();
        let d = UbuntuDetector::new();
        assert!(!d.can_handle(dir.path()).await.unwrap());
    }

    #[tokio::test]
    async fn extract_boot_info_finds_casper_kernel_and_initrd() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("casper")).unwrap();
        fs::write(dir.path().join("casper/vmlinuz"), b"fake-kernel").unwrap();
        fs::write(dir.path().join("casper/initrd"), b"fake-initrd").unwrap();

        let iso_info = IsoInfo {
            file_name: "ubuntu-24.04-live-server-amd64.iso".to_string(),
            file_path: dir.path().join("ubuntu-24.04-live-server-amd64.iso"),
            mount_path: dir.path().to_path_buf(),
            distro_type: DistroType::Ubuntu,
            kernel_path: PathBuf::new(),
            initrd_path: PathBuf::new(),
        };

        let d = UbuntuDetector::new();
        let boot_info = d.extract_boot_info(&iso_info).await.unwrap();

        assert_eq!(boot_info.kernel_path, dir.path().join("casper/vmlinuz"));
        assert_eq!(boot_info.initrd_path, dir.path().join("casper/initrd"));
        assert_eq!(boot_info.distro_type, DistroType::Ubuntu);
        // Normalized to "x86_64" (the Linux/Nix CPU-name convention, see
        // distro::arch), not Ubuntu's native "amd64" naming.
        assert_eq!(boot_info.architecture.as_deref(), Some("x86_64"));
    }

    #[tokio::test]
    async fn extract_boot_info_detects_arm64_as_aarch64() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("casper")).unwrap();
        fs::write(dir.path().join("casper/vmlinuz"), b"fake-kernel").unwrap();
        fs::write(dir.path().join("casper/initrd"), b"fake-initrd").unwrap();

        let iso_info = IsoInfo {
            file_name: "ubuntu-24.04-live-server-arm64.iso".to_string(),
            file_path: dir.path().join("ubuntu-24.04-live-server-arm64.iso"),
            mount_path: dir.path().to_path_buf(),
            distro_type: DistroType::Ubuntu,
            kernel_path: PathBuf::new(),
            initrd_path: PathBuf::new(),
        };

        let d = UbuntuDetector::new();
        let boot_info = d.extract_boot_info(&iso_info).await.unwrap();

        assert_eq!(boot_info.architecture.as_deref(), Some("aarch64"));
    }
}
