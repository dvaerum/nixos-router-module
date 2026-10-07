use crate::config::{AutoinstallScript, BootInfo, IsoInfo, MenuEntry};
use crate::distro::DistroDetector;
use crate::distro::detector::{AUTOINSTALL_DIR_URL_PLACEHOLDER, AUTOINSTALL_URL_PLACEHOLDER};
use crate::error::{PxeBootError, Result};
use percent_encoding::{AsciiSet, NON_ALPHANUMERIC, utf8_percent_encode};
use std::net::IpAddr;
use std::path::Path;

/// RFC 3986 "unreserved" characters (`-_.~` plus alphanumerics) left
/// unencoded for readability; everything else percent-encoded.
const URL_SEGMENT: &AsciiSet = &NON_ALPHANUMERIC
    .remove(b'-')
    .remove(b'_')
    .remove(b'.')
    .remove(b'~');

/// Percent-encodes a single path segment (an ISO filename or autoinstall
/// script name -- both operator-controlled, not just Nix-store-sourced)
/// before embedding it in a URL used inside GRUB's generated boot
/// commands. Two problems this solves at once: a real-world filename
/// containing a space (legal on most filesystems) previously produced a
/// URL GRUB's `linux`/`initrd` commands would mis-tokenize as two
/// arguments; and a filename containing GRUB-meaningful characters
/// (newline, `"`, `{`, `}`) could inject arbitrary GRUB script, since
/// these URL fields sit OUTSIDE a quoted GRUB string (unlike `title`,
/// see `grub::menu::escape_grub_string`) and get no quote-based escaping
/// at all.
fn url_encode_segment(s: &str) -> String {
    utf8_percent_encode(s, URL_SEGMENT).to_string()
}

pub struct MenuEntryFactory {
    gateway: IpAddr,
    http_port: u16,
}

impl MenuEntryFactory {
    pub fn new(gateway: IpAddr, http_port: u16) -> Self {
        Self { gateway, http_port }
    }

    pub fn create_entry(
        &self,
        iso_info: &IsoInfo,
        boot_info: &BootInfo,
        detector: &dyn DistroDetector,
        autoinstall: Option<&AutoinstallScript>,
        position: usize,
    ) -> Result<MenuEntry> {
        let grub_base = format!("(http,{}:{})", self.gateway, self.http_port);
        let iso_mount = format!(
            "{}/iso-mountpoint/{}",
            grub_base,
            url_encode_segment(&iso_info.file_name)
        );

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

        // Raw whole-ISO download (e.g. Ubuntu/casper's `url=` fetch), served
        // from the canonical `runtime_root/isos/` symlink tree (see
        // `iso::ServeTree`) rather than directly from whichever of the
        // (possibly multiple) `iso_folder_paths` the ISO actually lives in.
        let iso_url = format!(
            "http://{}:{}/isos/{}",
            self.gateway,
            self.http_port,
            url_encode_segment(&iso_info.file_name)
        );
        let mounted_url = format!(
            "http://{}:{}/iso-mountpoint/{}",
            self.gateway,
            self.http_port,
            url_encode_segment(&iso_info.file_name)
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
                self.gateway,
                self.http_port,
                url_encode_segment(&iso_info.file_name),
                url_encode_segment(&script.name)
            );
            let autoinstall_dir_url = format!("{}/", autoinstall_url);

            kernel_params = kernel_params
                .iter()
                .map(|param| {
                    param
                        .replace(AUTOINSTALL_DIR_URL_PLACEHOLDER, &autoinstall_dir_url)
                        .replace(AUTOINSTALL_URL_PLACEHOLDER, &autoinstall_url)
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::DistroType;
    use crate::distro::rhel::RhelDetector;
    use crate::distro::ubuntu::UbuntuDetector;
    use std::path::PathBuf;

    fn factory() -> MenuEntryFactory {
        MenuEntryFactory::new("192.168.75.1".parse().unwrap(), 1337)
    }

    fn iso_info() -> IsoInfo {
        IsoInfo {
            file_name: "rhel-9.6-x86_64-dvd.iso".to_string(),
            file_path: PathBuf::from("/srv/isos/rhel-9.6-x86_64-dvd.iso"),
            mount_path: PathBuf::from("/run/pxe-boot/iso-mountpoint/rhel-9.6-x86_64-dvd.iso"),
            distro_type: DistroType::RedHat,
            kernel_path: PathBuf::from(
                "/run/pxe-boot/iso-mountpoint/rhel-9.6-x86_64-dvd.iso/images/pxeboot/vmlinuz",
            ),
            initrd_path: PathBuf::from(
                "/run/pxe-boot/iso-mountpoint/rhel-9.6-x86_64-dvd.iso/images/pxeboot/initrd.img",
            ),
        }
    }

    fn boot_info() -> BootInfo {
        BootInfo {
            kernel_path: iso_info().kernel_path,
            initrd_path: iso_info().initrd_path,
            distro_type: DistroType::RedHat,
            version: None,
            architecture: Some("x86_64".to_string()),
            init_path: None,
        }
    }

    fn script(name: &str) -> AutoinstallScript {
        AutoinstallScript {
            name: name.to_string(),
            script_path: PathBuf::from(format!("/nix/store/xxx-{name}")),
        }
    }

    #[test]
    fn builds_kernel_and_initrd_urls_relative_to_mount() {
        let f = factory();
        let detector = RhelDetector::new();
        let entry = f
            .create_entry(&iso_info(), &boot_info(), &detector, None, 0)
            .unwrap();

        assert_eq!(
            entry.kernel_url,
            "(http,192.168.75.1:1337)/iso-mountpoint/rhel-9.6-x86_64-dvd.iso/images/pxeboot/vmlinuz"
        );
        assert_eq!(
            entry.initrd_url,
            "(http,192.168.75.1:1337)/iso-mountpoint/rhel-9.6-x86_64-dvd.iso/images/pxeboot/initrd.img"
        );
        assert_eq!(entry.title, "rhel-9.6-x86_64-dvd.iso");
        assert_eq!(entry.position, 0);
        // A6: MenuEntry.architecture must come from BootInfo.architecture
        // (consumed by GrubMenuBuilder's $grub_cpu filtering), not be
        // silently dropped on the way from detector to rendered entry.
        assert_eq!(entry.architecture.as_deref(), Some("x86_64"));
    }

    #[test]
    fn title_includes_script_name_when_autoinstall_present() {
        let f = factory();
        let detector = RhelDetector::new();
        let s = script("server.ks");
        let entry = f
            .create_entry(&iso_info(), &boot_info(), &detector, Some(&s), 2)
            .unwrap();

        assert_eq!(entry.title, "rhel-9.6-x86_64-dvd.iso (server.ks)");
        assert_eq!(entry.position, 2);
    }

    #[test]
    fn substitutes_autoinstall_url_placeholder() {
        let f = factory();
        let detector = RhelDetector::new();
        let s = script("server.ks");
        let entry = f
            .create_entry(&iso_info(), &boot_info(), &detector, Some(&s), 0)
            .unwrap();

        let ks_param = entry
            .kernel_params
            .iter()
            .find(|p| p.starts_with("inst.ks="))
            .expect("inst.ks= param missing");
        assert_eq!(
            ks_param,
            "inst.ks=http://192.168.75.1:1337/unattented-install/rhel-9.6-x86_64-dvd.iso/server.ks"
        );
        // The placeholder itself must not survive substitution.
        assert!(!entry.kernel_params.iter().any(|p| p.contains("{autoinstall_url}")));
    }

    #[test]
    fn substitutes_autoinstall_dir_url_placeholder_with_trailing_slash() {
        let ubuntu_iso = IsoInfo {
            file_name: "ubuntu-24.04-live-server-amd64.iso".to_string(),
            file_path: PathBuf::from("/srv/isos/ubuntu-24.04-live-server-amd64.iso"),
            mount_path: PathBuf::from(
                "/run/pxe-boot/iso-mountpoint/ubuntu-24.04-live-server-amd64.iso",
            ),
            distro_type: DistroType::Ubuntu,
            kernel_path: PathBuf::from(
                "/run/pxe-boot/iso-mountpoint/ubuntu-24.04-live-server-amd64.iso/casper/vmlinuz",
            ),
            initrd_path: PathBuf::from(
                "/run/pxe-boot/iso-mountpoint/ubuntu-24.04-live-server-amd64.iso/casper/initrd",
            ),
        };
        let ubuntu_boot_info = BootInfo {
            kernel_path: ubuntu_iso.kernel_path.clone(),
            initrd_path: ubuntu_iso.initrd_path.clone(),
            distro_type: DistroType::Ubuntu,
            version: None,
            architecture: Some("amd64".to_string()),
            init_path: None,
        };
        let f = factory();
        let detector = UbuntuDetector::new();
        let s = script("minimal.ks");
        let entry = f
            .create_entry(&ubuntu_iso, &ubuntu_boot_info, &detector, Some(&s), 0)
            .unwrap();

        let ds_param = entry
            .kernel_params
            .iter()
            .find(|p| p.starts_with("ds=nocloud-net"))
            .expect("ds= param missing");
        assert_eq!(
            ds_param,
            "ds=nocloud-net\\;s=http://192.168.75.1:1337/unattented-install/ubuntu-24.04-live-server-amd64.iso/minimal.ks/"
        );
    }

    #[test]
    fn errors_when_kernel_path_is_not_under_mount_path() {
        let f = factory();
        let detector = RhelDetector::new();
        let mut bad_boot_info = boot_info();
        // Simulate a bug elsewhere handing in a kernel path from a
        // completely different ISO's mount -- `strip_prefix` must fail
        // cleanly rather than silently producing a bogus URL.
        bad_boot_info.kernel_path = PathBuf::from("/some/unrelated/path/vmlinuz");

        let result = f.create_entry(&iso_info(), &bad_boot_info, &detector, None, 0);
        assert!(result.is_err());
    }

    #[test]
    fn errors_when_initrd_path_is_not_under_mount_path() {
        // Symmetric to the kernel_path case above -- same strip_prefix
        // pattern, same failure mode, previously untested.
        let f = factory();
        let detector = RhelDetector::new();
        let mut bad_boot_info = boot_info();
        bad_boot_info.initrd_path = PathBuf::from("/some/unrelated/path/initrd.img");

        let result = f.create_entry(&iso_info(), &bad_boot_info, &detector, None, 0);
        assert!(result.is_err());
    }

    #[test]
    fn url_fields_are_percent_encoded_for_filenames_with_spaces_and_grub_metachars() {
        // Real-world ISO filenames routinely contain spaces (a literal
        // space is not a valid URL token, and would previously have been
        // mis-tokenized by GRUB's `linux`/`initrd` commands as two
        // separate arguments). A filename containing GRUB-meaningful
        // characters must not be able to inject script, either --
        // these URL fields sit OUTSIDE a quoted GRUB string (unlike
        // `title`), so they get no quote-based escaping at all.
        let dangerous_name = "Ubuntu Server\"; menuentry \"evil".to_string();
        let iso_info = IsoInfo {
            file_name: dangerous_name.clone(),
            file_path: PathBuf::from(format!("/srv/isos/{dangerous_name}")),
            mount_path: PathBuf::from(format!("/run/pxe-boot/iso-mountpoint/{dangerous_name}")),
            distro_type: DistroType::RedHat,
            kernel_path: PathBuf::from(format!(
                "/run/pxe-boot/iso-mountpoint/{dangerous_name}/images/pxeboot/vmlinuz"
            )),
            initrd_path: PathBuf::from(format!(
                "/run/pxe-boot/iso-mountpoint/{dangerous_name}/images/pxeboot/initrd.img"
            )),
        };
        let boot_info = BootInfo {
            kernel_path: iso_info.kernel_path.clone(),
            initrd_path: iso_info.initrd_path.clone(),
            distro_type: DistroType::RedHat,
            version: None,
            architecture: Some("x86_64".to_string()),
            init_path: None,
        };

        let f = factory();
        let detector = RhelDetector::new();
        let entry = f
            .create_entry(&iso_info, &boot_info, &detector, None, 0)
            .unwrap();

        // No raw space, quote, or brace may survive into the URL fields.
        for field in [&entry.kernel_url, &entry.initrd_url] {
            assert!(!field.contains(' '), "unescaped space in {field:?}");
            assert!(!field.contains('"'), "unescaped quote in {field:?}");
            assert!(!field.contains('{'), "unescaped brace in {field:?}");
        }
        // `inst.repo=` is built from `mounted_url`, which embeds the same
        // file_name -- check it too via the RHEL-specific param.
        let repo_param = entry
            .kernel_params
            .iter()
            .find(|p| p.starts_with("inst.repo="))
            .expect("inst.repo= param missing");
        assert!(!repo_param.contains(' '));
        assert!(!repo_param.contains('"'));
    }
}
