use crate::config::{AutoinstallScript, BootInfo, DistroType, IsoInfo};
use crate::distro::detector::DistroDetector;
use crate::error::{PxeBootError, Result};
use async_trait::async_trait;
use serde::Deserialize;
use std::path::{Path, PathBuf};

/// RFC-0125 "bootspec" (https://github.com/NixOS/rfcs/pull/125): the
/// standard, stable JSON document every NixOS generation's toplevel
/// closure carries at `<toplevel>/boot.json`, "depended upon by external
/// tooling" per nixpkgs' own `bootspec.nix` comment -- literally designed
/// for exactly the kind of discovery this detector needs (kernel, initrd,
/// and init path for a specific generation), rather than guessing at
/// filenames or re-deriving a content-addressed store path independently.
#[derive(Debug, Deserialize)]
struct BootSpecDocument {
    #[serde(rename = "org.nixos.bootspec.v1")]
    v1: BootSpecV1,
}

#[derive(Debug, Deserialize)]
struct BootSpecV1 {
    init: String,
    initrd: String,
    kernel: String,
    // Always present (part of the unconditional base merge in nixpkgs'
    // own bootspec.nix, not gated by any `optionalAttrs`) -- a Nix
    // "system" double like "x86_64-linux"/"aarch64-linux". The
    // authoritative source for this ISO's real architecture (see
    // `architecture_from_system` below), replacing a hardcoded
    // "x86_64" literal that was wrong for any aarch64 NixOS ISO this
    // project's own `modules/iso-builder` can already produce
    // (`iso-aarch64` in flake.nix).
    system: String,
}

/// Nix "system" doubles are `<cpu>-<kernel>` (cpu never contains a
/// hyphen for any real-world target) -- the part before the first `-`
/// is exactly GRUB's own notion of CPU architecture (see A6's
/// `$grub_cpu`-based filtering, which consumes this value).
fn architecture_from_system(system: &str) -> Option<String> {
    system.split_once('-').map(|(cpu, _os)| cpu.to_string())
}


pub struct NixOsDetector;

impl NixOsDetector {
    pub fn new() -> Self {
        Self
    }

    /// Reads `<mount>/boot.json`, exposed at the ISO's top level by this
    /// project's own `modules/iso-builder` (mirroring how nixpkgs' own
    /// `iso-image.nix` already exposes the kernel/initrd under `/boot/` --
    /// GRUB can't easily read inside the nested `nix-store.squashfs`
    /// without its own mount, and neither can this tool without adding
    /// squashfs-mounting support). Not present on stock/third-party NixOS
    /// ISOs that don't carry this project's module -- such ISOs are not
    /// supported by this detector at all (see `extract_boot_info`): there
    /// is no authoritative, non-guessed way to discover `init=` without
    /// bootspec, and guessing by filename previously produced ISOs that
    /// mounted successfully but failed to boot (missing `init=`).
    async fn read_bootspec(mount: &Path) -> Result<BootSpecV1> {
        let path = mount.join("boot.json");
        let contents =
            tokio::fs::read_to_string(&path)
                .await
                .map_err(|e| PxeBootError::DetectionFailed {
                    iso: mount.display().to_string(),
                    reason: format!("boot.json not readable at {}: {e}", path.display()),
                })?;
        let doc: BootSpecDocument =
            serde_json::from_str(&contents).map_err(|e| PxeBootError::DetectionFailed {
                iso: mount.display().to_string(),
                reason: format!("boot.json did not parse as bootspec v1: {e}"),
            })?;
        Ok(doc.v1)
    }

    /// Bootspec's `kernel`/`initrd` fields are the ABSOLUTE nix store paths
    /// as they'll exist once the real system is mounted (e.g.
    /// `/nix/store/<hash>-linux-.../bzImage`) -- not directly readable from
    /// the ISO9660-mounted `mount` path. nixpkgs' `iso-image.nix` also
    /// copies the kernel/initrd to `/boot/<that same absolute path>` on the
    /// ISO (for GRUB), so that's where we actually read the bytes from.
    fn resolve_on_iso(mount: &Path, absolute_store_path: &str) -> PathBuf {
        mount
            .join("boot")
            .join(absolute_store_path.trim_start_matches('/'))
    }
}

#[async_trait]
impl DistroDetector for NixOsDetector {
    fn id(&self) -> &str {
        "nixos"
    }

    fn priority(&self) -> u8 {
        60
    }

    async fn can_handle(&self, mount_path: &Path) -> Result<bool> {
        // Check for nix-store.squashfs
        let squashfs = mount_path.join("nix-store.squashfs");
        Ok(squashfs.exists())
    }

    async fn extract_boot_info(&self, iso_info: &IsoInfo) -> Result<BootInfo> {
        let mount = &iso_info.mount_path;

        let bootspec = Self::read_bootspec(mount).await?;
        let kernel = Self::resolve_on_iso(mount, &bootspec.kernel);
        let initrd = Self::resolve_on_iso(mount, &bootspec.initrd);

        // Hard-fail rather than guess: a boot.json that references a
        // kernel/initrd not actually present on the ISO is just as
        // unusable as a missing/malformed boot.json -- there is no
        // authoritative fallback source for these paths (see module-level
        // doc comment on `read_bootspec`).
        if !kernel.is_file() {
            return Err(PxeBootError::DetectionFailed {
                iso: mount.display().to_string(),
                reason: format!(
                    "boot.json referenced kernel not found on ISO: {}",
                    kernel.display()
                ),
            });
        }
        if !initrd.is_file() {
            return Err(PxeBootError::DetectionFailed {
                iso: mount.display().to_string(),
                reason: format!(
                    "boot.json referenced initrd not found on ISO: {}",
                    initrd.display()
                ),
            });
        }

        Ok(BootInfo {
            kernel_path: kernel,
            initrd_path: initrd,
            distro_type: DistroType::NixOS,
            version: None,
            architecture: architecture_from_system(&bootspec.system),
            init_path: Some(bootspec.init),
        })
    }

    fn generate_boot_params(
        &self,
        iso_url: &str,
        _mounted_url: &str,
        boot_info: &BootInfo,
        _autoinstall: Option<&AutoinstallScript>,
    ) -> Vec<String> {
        // For PXE boot, we load kernel/initrd directly from mounted ISO
        // The initrd downloads the full ISO to continue booting via findiso parameter
        // NOTE: This requires the ISO to be built with enableNetworkDownload = true
        let mut params = vec![
            format!("findiso={}", iso_url),
            // No root=LABEL=... needed: under systemd stage-1, nixpkgs' own
            // cd-dvd module makes `/` plain tmpfs (no root device at all)
            // and mounts the ISO at `/iso` as a `neededForBoot` filesystem
            // instead -- `findiso-download`'s loop device satisfies that
            // mount's own by-label device dependency directly (see
            // modules/iso-builder/default.nix).
            "boot.shell_on_fail".to_string(),
            "nohibernate".to_string(),
            // Increase loglevel to debug boot issues
            "loglevel=7".to_string(),
            "lsm=landlock,yama,bpf".to_string(),
            // Without this, kernel output only goes to the VGA console,
            // invisible to serial-only capture (e.g. nixosTest's VM logs).
            // Serial only (not also tty0): the kernel treats the LAST
            // console= as preferred for later output, so listing both
            // silently stops routing to serial once systemd takes over.
            "console=ttyS0,115200".to_string(),
        ];

        // Without `init=`, systemd stage-1's `initrd-find-nixos-closure.service`
        // has no way to know which closure to switch-root into ("No init=
        // parameter on the kernel command line"), failing the whole boot
        // into emergency mode right after all filesystems (including the
        // network-downloaded ISO) have mounted successfully. A normal
        // (non-network) ISO boot gets this for free from the ISO's own
        // self-contained GRUB config; PXE boot constructs its own command
        // line and bypasses that config entirely, so it must be restated
        // here from the value discovered in extract_boot_info.
        if let Some(init) = &boot_info.init_path {
            params.push(format!("init={}", init));
        }

        params
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn architecture_from_system_splits_cpu_from_kernel() {
        assert_eq!(
            architecture_from_system("x86_64-linux").as_deref(),
            Some("x86_64")
        );
        assert_eq!(
            architecture_from_system("aarch64-linux").as_deref(),
            Some("aarch64")
        );
    }

    #[test]
    fn architecture_from_system_returns_none_without_a_hyphen() {
        assert_eq!(architecture_from_system("garbage"), None);
    }

    fn write_iso_fixture(root: &Path, bootspec: Option<&str>) -> IsoInfo {
        let kernel_rel = "nix/store/aaa-linux-1.0/bzImage";
        let initrd_rel = "nix/store/bbb-initrd-linux-1.0/initrd";
        fs::create_dir_all(root.join("boot").join("nix/store/aaa-linux-1.0")).unwrap();
        fs::create_dir_all(root.join("boot").join("nix/store/bbb-initrd-linux-1.0")).unwrap();
        fs::write(root.join("boot").join(kernel_rel), b"fake-kernel").unwrap();
        fs::write(root.join("boot").join(initrd_rel), b"fake-initrd").unwrap();
        fs::write(root.join("nix-store.squashfs"), b"fake-squashfs").unwrap();

        if let Some(json) = bootspec {
            fs::write(root.join("boot.json"), json).unwrap();
        }

        IsoInfo {
            file_name: "test.iso".to_string(),
            file_path: root.join("test.iso"),
            mount_path: root.to_path_buf(),
            distro_type: DistroType::NixOS,
            kernel_path: root.join("boot").join(kernel_rel),
            initrd_path: root.join("boot").join(initrd_rel),
        }
    }

    #[tokio::test]
    async fn uses_bootspec_when_boot_json_present() {
        let dir = tempfile::tempdir().unwrap();
        let bootspec = r#"{
            "org.nixos.bootspec.v1": {
                "init": "/nix/store/ccc-nixos-system-test/init",
                "initrd": "/nix/store/bbb-initrd-linux-1.0/initrd",
                "kernel": "/nix/store/aaa-linux-1.0/bzImage",
                "system": "x86_64-linux"
            }
        }"#;
        let iso_info = write_iso_fixture(dir.path(), Some(bootspec));

        let detector = NixOsDetector::new();
        let boot_info = detector.extract_boot_info(&iso_info).await.unwrap();

        assert_eq!(
            boot_info.kernel_path,
            dir.path().join("boot/nix/store/aaa-linux-1.0/bzImage")
        );
        assert_eq!(
            boot_info.initrd_path,
            dir.path()
                .join("boot/nix/store/bbb-initrd-linux-1.0/initrd")
        );
        assert_eq!(
            boot_info.init_path.as_deref(),
            Some("/nix/store/ccc-nixos-system-test/init")
        );
        assert_eq!(boot_info.architecture.as_deref(), Some("x86_64"));
    }

    #[tokio::test]
    async fn errors_without_boot_json() {
        let dir = tempfile::tempdir().unwrap();
        let iso_info = write_iso_fixture(dir.path(), None);

        let detector = NixOsDetector::new();
        let result = detector.extract_boot_info(&iso_info).await;

        // No boot.json at all -- there is no authoritative source for
        // init=, and guessing by filename previously produced ISOs that
        // mounted but failed to boot. Hard-fail instead of guessing.
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn errors_when_boot_json_is_malformed() {
        let dir = tempfile::tempdir().unwrap();
        let iso_info = write_iso_fixture(dir.path(), Some("not valid json"));

        let detector = NixOsDetector::new();
        let result = detector.extract_boot_info(&iso_info).await;

        assert!(result.is_err());
    }

    #[tokio::test]
    async fn errors_when_bootspec_is_missing_the_system_field() {
        // `system` is unconditionally present in every real bootspec v1
        // document nixpkgs produces (see nixos.rs's doc comment on
        // `BootSpecV1::system`) -- a boot.json missing it is just as
        // malformed/untrustworthy as one missing kernel/initrd/init.
        let dir = tempfile::tempdir().unwrap();
        let bootspec = r#"{
            "org.nixos.bootspec.v1": {
                "init": "/nix/store/ccc-nixos-system-test/init",
                "initrd": "/nix/store/bbb-initrd-linux-1.0/initrd",
                "kernel": "/nix/store/aaa-linux-1.0/bzImage"
            }
        }"#;
        let iso_info = write_iso_fixture(dir.path(), Some(bootspec));

        let detector = NixOsDetector::new();
        let result = detector.extract_boot_info(&iso_info).await;

        assert!(result.is_err());
    }

    #[tokio::test]
    async fn aarch64_system_yields_aarch64_architecture() {
        let dir = tempfile::tempdir().unwrap();
        let bootspec = r#"{
            "org.nixos.bootspec.v1": {
                "init": "/nix/store/ccc-nixos-system-test/init",
                "initrd": "/nix/store/bbb-initrd-linux-1.0/initrd",
                "kernel": "/nix/store/aaa-linux-1.0/bzImage",
                "system": "aarch64-linux"
            }
        }"#;
        let iso_info = write_iso_fixture(dir.path(), Some(bootspec));

        let detector = NixOsDetector::new();
        let boot_info = detector.extract_boot_info(&iso_info).await.unwrap();

        assert_eq!(boot_info.architecture.as_deref(), Some("aarch64"));
    }

    #[tokio::test]
    async fn errors_when_referenced_kernel_missing_on_iso() {
        let dir = tempfile::tempdir().unwrap();
        let iso_info = write_iso_fixture(dir.path(), None);
        // A valid, parseable bootspec, but pointing at a kernel path that
        // doesn't actually exist on the ISO (e.g. a boot.json left over
        // from a different build, or a corrupted ISO) -- same treatment
        // as missing/malformed boot.json: hard-fail, don't guess.
        let bootspec = r#"{
            "org.nixos.bootspec.v1": {
                "init": "/nix/store/ccc-nixos-system-test/init",
                "initrd": "/nix/store/bbb-initrd-linux-1.0/initrd",
                "kernel": "/nix/store/does-not-exist/bzImage",
                "system": "x86_64-linux"
            }
        }"#;
        fs::write(dir.path().join("boot.json"), bootspec).unwrap();

        let detector = NixOsDetector::new();
        let result = detector.extract_boot_info(&iso_info).await;

        assert!(result.is_err());
    }

    #[test]
    fn generates_init_param_when_present() {
        let detector = NixOsDetector::new();
        let boot_info = BootInfo {
            kernel_path: PathBuf::from("/tmp/bzImage"),
            initrd_path: PathBuf::from("/tmp/initrd"),
            distro_type: DistroType::NixOS,
            version: None,
            architecture: Some("x86_64".to_string()),
            init_path: Some("/nix/store/ccc-nixos-system-test/init".to_string()),
        };
        let params = detector.generate_boot_params(
            "http://gw:1338/i.iso",
            "http://gw:1337/m",
            &boot_info,
            None,
        );
        assert!(params.contains(&"init=/nix/store/ccc-nixos-system-test/init".to_string()));
    }

    #[test]
    fn omits_init_param_when_absent() {
        let detector = NixOsDetector::new();
        let boot_info = BootInfo {
            kernel_path: PathBuf::from("/tmp/bzImage"),
            initrd_path: PathBuf::from("/tmp/initrd"),
            distro_type: DistroType::NixOS,
            version: None,
            architecture: Some("x86_64".to_string()),
            init_path: None,
        };
        let params = detector.generate_boot_params(
            "http://gw:1338/i.iso",
            "http://gw:1337/m",
            &boot_info,
            None,
        );
        assert!(!params.iter().any(|p| p.starts_with("init=")));
    }
}
