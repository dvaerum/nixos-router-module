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
        let mut params = vec!["ip=dhcp".to_string(), format!("url={}", iso_url)];

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
