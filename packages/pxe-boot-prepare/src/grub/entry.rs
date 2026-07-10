use crate::config::{AutoinstallScript, BootInfo, IsoInfo, MenuEntry};
use crate::distro::DistroDetector;
use crate::error::{PxeBootError, Result};
use std::net::IpAddr;
use std::path::Path;

pub struct MenuEntryFactory {
    gateway: IpAddr,
    http_mount_port: u16,
    http_iso_port: u16,
}

impl MenuEntryFactory {
    pub fn new(gateway: IpAddr, http_mount_port: u16, http_iso_port: u16) -> Self {
        Self {
            gateway,
            http_mount_port,
            http_iso_port,
        }
    }

    pub fn create_entry(
        &self,
        iso_info: &IsoInfo,
        boot_info: &BootInfo,
        detector: &dyn DistroDetector,
        autoinstall: Option<&AutoinstallScript>,
        position: usize,
    ) -> Result<MenuEntry> {
        let grub_base = format!("(http,{}:{})", self.gateway, self.http_mount_port);
        let iso_mount = format!("{}/iso-mountpoint/{}", grub_base, iso_info.file_name);

        let kernel_rel = boot_info
            .kernel_path
            .strip_prefix(&iso_info.mount_path)
            .map_err(|_| PxeBootError::GrubGeneration("Invalid kernel path".into()))?;

        let initrd_rel = boot_info
            .initrd_path
            .strip_prefix(&iso_info.mount_path)
            .map_err(|_| PxeBootError::GrubGeneration("Invalid initrd path".into()))?;

        let kernel_url = format!("{}/{}", iso_mount, Self::path_to_url(kernel_rel));
        let initrd_url = format!("{}/{}", iso_mount, Self::path_to_url(initrd_rel));

        let iso_url = format!(
            "http://{}:{}/{}",
            self.gateway, self.http_iso_port, iso_info.file_name
        );
        let mounted_url = format!(
            "http://{}:{}/iso-mountpoint/{}",
            self.gateway, self.http_mount_port, iso_info.file_name
        );

        let title = if let Some(script) = autoinstall {
            format!("{} ({})", iso_info.file_name, script.name)
        } else {
            iso_info.file_name.clone()
        };

        let mut kernel_params =
            detector.generate_boot_params(&iso_url, &mounted_url, autoinstall);

        // Replace autoinstall URL placeholders if present.
        // - `{autoinstall_url}`     → the seed *file* (e.g. RHEL `inst.ks=`).
        // - `{autoinstall_dir_url}` → the seed *directory* ending in `/`
        //   (e.g. Ubuntu NoCloud `s=`); each script's seed lives in its own
        //   `.../{iso}/{script.name}/` dir written by AutoinstallManager.
        if let Some(script) = autoinstall {
            let autoinstall_url = format!(
                "http://{}:{}/unattented-install/{}/{}",
                self.gateway, self.http_mount_port, iso_info.file_name, script.name
            );
            let autoinstall_dir_url = format!("{}/", autoinstall_url);

            kernel_params = kernel_params
                .iter()
                .map(|param| {
                    param
                        .replace("{autoinstall_dir_url}", &autoinstall_dir_url)
                        .replace("{autoinstall_url}", &autoinstall_url)
                })
                .collect();
        }

        Ok(MenuEntry {
            title,
            kernel_url,
            kernel_params,
            initrd_url,
            position,
        })
    }

    fn path_to_url(path: &Path) -> String {
        path.to_string_lossy().replace('\\', "/")
    }
}
