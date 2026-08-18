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
            params.push("ds=nocloud-net\\;s={autoinstall_dir_url}".to_string());
        }

        params
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn script() -> AutoinstallScript {
        AutoinstallScript {
            name: "minimal-environment.yaml".to_string(),
            script_path: PathBuf::from("/nix/store/xxx-minimal-environment.yaml"),
        }
    }

    #[test]
    fn boots_from_iso_url() {
        let d = UbuntuDetector::new();
        let params = d.generate_boot_params(
            "http://gw:1338/ubuntu.iso",
            "http://gw:1337/iso-mountpoint/ubuntu.iso",
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
            None,
        );
        assert!(params.contains(&"BOOTIF=${net_default_mac}".to_string()));
        assert!(!params.iter().any(|p| p.contains("enp") || p.contains("eth")));
    }

    #[test]
    fn adds_autoinstall_and_nocloud_when_script_present() {
        let d = UbuntuDetector::new();
        let s = script();
        let params = d.generate_boot_params("http://gw:1338/ubuntu.iso", "http://m", Some(&s));
        assert!(params.contains(&"url=http://gw:1338/ubuntu.iso".to_string()));
        assert!(params.contains(&"autoinstall".to_string()));
        // The dir-URL placeholder is substituted later by MenuEntryFactory; the
        // semicolon is escaped so GRUB keeps it as a single argument.
        assert!(params.contains(&"ds=nocloud-net\\;s={autoinstall_dir_url}".to_string()));
    }

    #[test]
    fn no_autoinstall_args_when_script_absent() {
        let d = UbuntuDetector::new();
        let params = d.generate_boot_params("http://i", "http://m", None);
        assert!(!params.contains(&"autoinstall".to_string()));
        assert!(!params.iter().any(|p| p.starts_with("ds=")));
    }
}
