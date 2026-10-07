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
        // (`netboot=nfs`), which requires serving the ISO tree over NFS — deferred
        // until the module grows an NFS server.
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

        // Ubuntu Server (subiquity) unattended install. `autoinstall` runs the
        // installer non-interactively; `ds=nocloud-net;s=<dir>/` points cloud-init
        // at the directory serving `user-data` + `meta-data`. The semicolon is
        // escaped (`\;`) so GRUB treats the whole value as one kernel argument.
        // `{autoinstall_dir_url}` (a directory URL ending in `/`) is substituted
        // by MenuEntryFactory.
        if autoinstall.is_some() {
            params.push("autoinstall".to_string());
            params.push(format!("ds=nocloud-net\\;s={AUTOINSTALL_DIR_URL_PLACEHOLDER}"));
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
        // Normalized to "x86_64" (GRUB's own $grub_cpu convention, see
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
