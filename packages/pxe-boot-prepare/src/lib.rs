pub mod autoinstall;
pub mod config;
pub mod distro;
pub mod error;
pub mod grub;
pub mod iso;

use autoinstall::AutoinstallManager;
use config::{BootInfo, DhcpInterface, DistroType, IsoInfo, PxeBootConfig};
use distro::{DetectorRegistry, DistroDetector};
use error::{IoResultExt, PxeBootError, Result};
use grub::{GrubMenuBuilder, MenuEntryFactory};
use iso::{IsoDiscovery, IsoMounter};

pub struct PxeBootService {
    config: PxeBootConfig,
    detector_registry: DetectorRegistry,
    iso_discovery: IsoDiscovery,
    iso_mounter: IsoMounter,
    autoinstall_manager: AutoinstallManager,
}

impl PxeBootService {
    pub fn new(config: PxeBootConfig) -> Self {
        let detector_registry = DetectorRegistry::new();
        let iso_discovery = IsoDiscovery::new(config.iso_folder_path.clone());
        let iso_mounter = IsoMounter::new(config.runtime_root.clone());
        let autoinstall_manager = AutoinstallManager::new(config.runtime_root.clone());

        Self {
            config,
            detector_registry,
            iso_discovery,
            iso_mounter,
            autoinstall_manager,
        }
    }

    /// Main entry point: prepare PXE boot environment
    pub async fn prepare(&self) -> Result<()> {
        tracing::info!("Starting PXE boot preparation");

        // 1. Discover ISOs
        let iso_paths = self.iso_discovery.discover().await?;
        tracing::info!("Discovered {} ISO files", iso_paths.len());

        if iso_paths.is_empty() {
            tracing::warn!("No ISO files found in {}", self.config.iso_folder_path.display());
            return Ok(());
        }

        // 2. Mount all ISOs (in parallel), skipping failures
        let mut mount_tasks = Vec::new();
        for path in &iso_paths {
            mount_tasks.push(self.iso_mounter.mount(path));
        }

        let mount_results = futures::future::join_all(mount_tasks).await;

        // Collect successfully mounted ISOs
        let mut mounted_isos = Vec::new();
        for (iso_path, mount_result) in iso_paths.iter().zip(mount_results.iter()) {
            match mount_result {
                Ok(mount_path) => {
                    mounted_isos.push((iso_path.clone(), mount_path.clone()));
                }
                Err(e) => {
                    tracing::warn!(
                        "Failed to mount {}: {}. Skipping this ISO.",
                        iso_path.display(),
                        e
                    );
                }
            }
        }

        if mounted_isos.is_empty() {
            tracing::warn!("No ISOs could be mounted successfully. GRUB menus will only have reload entry.");
        } else {
            tracing::info!("Successfully mounted {} ISOs", mounted_isos.len());
        }

        // 3. Detect distributions and extract boot info
        let mut iso_infos = Vec::new();

        for (iso_path, mount_path) in mounted_isos.iter() {
            // A path with no final component (e.g. "/", or "..") can't
            // happen for a real discovered ISO in practice, but panicking
            // here would take down detection for every OTHER ISO too --
            // skip just this one instead, matching the isolation already
            // applied to mount/detect failures below.
            let Some(file_name) = iso_path.file_name() else {
                tracing::warn!(
                    "Skipping {}: no file name component in path.",
                    iso_path.display()
                );
                continue;
            };
            let file_name = file_name.to_string_lossy().to_string();

            // Try to detect and extract boot info, skip on failure
            match self.detector_registry.detect(mount_path).await {
                Ok(detector) => {
                    let mut iso_info = IsoInfo::placeholder(
                        file_name.clone(),
                        iso_path.clone(),
                        mount_path.clone(),
                    );

                    match detector.extract_boot_info(&iso_info).await {
                        Ok(boot_info) => {
                            iso_info.apply_boot_info(&boot_info);

                            tracing::info!(
                                "Detected {} as {:?}",
                                file_name,
                                boot_info.distro_type
                            );

                            iso_infos.push((iso_info, boot_info, detector));
                        }
                        Err(e) => {
                            tracing::warn!(
                                "Failed to extract boot info from {}: {}. Skipping this ISO.",
                                file_name,
                                e
                            );
                        }
                    }
                }
                Err(e) => {
                    tracing::warn!(
                        "Failed to detect distribution type for {}: {}. Skipping this ISO.",
                        file_name,
                        e
                    );
                }
            }
        }

        if iso_infos.is_empty() {
            tracing::warn!("No distributions detected. GRUB menus will be empty.");
            // Still continue to set up the infrastructure
        } else {
            tracing::info!("Detected {} distributions", iso_infos.len());
        }

        // 4. Process autoinstall scripts. Pass the already-detected distro per ISO
        //    so the manager can lay out each seed the way that installer expects
        //    (e.g. Ubuntu NoCloud user-data/meta-data vs RHEL kickstart).
        let distro_by_iso: std::collections::HashMap<String, DistroType> = iso_infos
            .iter()
            .map(|(iso_info, _, _)| (iso_info.file_name.clone(), iso_info.distro_type.clone()))
            .collect();
        // A failure here (e.g. one unreadable autoinstall script source)
        // must not abort menu generation below -- GRUB menus without a
        // working autoinstall seed are still useful (manual install still
        // works), same isolation rationale as the raw-ISO tree above.
        if let Err(e) = self
            .autoinstall_manager
            .prepare(&self.config, &distro_by_iso)
            .await
        {
            tracing::warn!(
                "Failed to prepare autoinstall scripts: {}. Autoinstall entries may be missing or stale until the next successful run.",
                e
            );
        }

        // Soft-validate default_iso/default_script against what was
        // actually discovered -- a mismatch here just means the
        // configured default silently never takes effect (GRUB falls
        // back to no default/manual selection), not a fatal error, but
        // worth surfacing since it's easy to typo an ISO filename or
        // script name in the Nix config.
        let discovered_iso_names: std::collections::HashSet<String> = iso_infos
            .iter()
            .map(|(iso_info, _, _)| iso_info.file_name.clone())
            .collect();
        for warning in check_default_entry_warnings(
            &self.config.dhcp_interfaces,
            &discovered_iso_names,
            &self.config.autoinstall,
        ) {
            tracing::warn!("{}", warning);
        }

        // 5. Generate GRUB menus for each DHCP interface, isolating failures
        //    so one broken interface's menu doesn't abort preparation for
        //    the rest (mirrors the per-ISO skip+warn pattern above).
        //
        // C34: each interface writes to its own `tftp_root`/`rootFor`
        // (independent paths, confirmed by C23's per-interface
        // `ReadWritePaths` hardening), so generating all of them
        // concurrently is safe -- unlike ISO mounting above, which stays
        // strictly sequential after a real kernel-level loop-device race.
        let results = futures::future::join_all(
            self.config
                .dhcp_interfaces
                .iter()
                .map(|interface| self.generate_grub_menu(interface, &iso_infos, &failed_isos)),
        )
        .await;

        for (interface, result) in self.config.dhcp_interfaces.iter().zip(results) {
            if let Err(e) = result {
                tracing::warn!(
                    "Failed to generate GRUB menu for interface {} (ID: {}): {}. Skipping this interface.",
                    interface.name,
                    interface.id,
                    e
                );
            }
        }

        tracing::info!("PXE boot preparation complete");
        Ok(())
    }

    async fn generate_grub_menu(
        &self,
        interface: &DhcpInterface,
        iso_infos: &[(IsoInfo, BootInfo, &dyn DistroDetector)],
    ) -> Result<()> {
        let mut builder = GrubMenuBuilder::new()?;
        
        let factory = MenuEntryFactory::new(interface.gateway, self.config.http.port);

        let mut position = 0;
        let mut default_position = None;

        for (iso_info, boot_info, detector) in iso_infos {
            // Base entry (no autoinstall). A single bad entry (e.g. an
            // unrepresentable path) must not abort the whole menu for
            // this interface -- skip just this ISO and keep going.
            let entry = match factory.create_entry(iso_info, boot_info, *detector, None, position)
            {
                Ok(entry) => entry,
                Err(e) => {
                    tracing::warn!(
                        "Failed to create GRUB entry for {}: {}. Skipping this ISO.",
                        iso_info.file_name,
                        e
                    );
                    continue;
                }
            };

            // Check if base entry (no script) should be the default
            if let Some(default_iso) = &interface.default_iso {
                if default_iso == &iso_info.file_name {
                    // If default_script is empty or None, this base entry is the default
                    if interface.default_script.is_none() || interface.default_script.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
                        default_position = Some(position);
                    }
                }
            }

            builder.add_entry(entry);
            position += 1;

            // Autoinstall entries
            if let Some(scripts) = self.config.autoinstall.get(&iso_info.file_name) {
                for script in scripts {
                    // Same isolation, one level deeper: a bad autoinstall
                    // entry only skips that one script, not the ISO's
                    // base entry (already added above) nor the rest of
                    // the menu.
                    let entry = match factory.create_entry(
                        iso_info,
                        boot_info,
                        *detector,
                        Some(script),
                        position,
                    ) {
                        Ok(entry) => entry,
                        Err(e) => {
                            tracing::warn!(
                                "Failed to create GRUB autoinstall entry for {} ({}): {}. Skipping this entry.",
                                iso_info.file_name,
                                script.name,
                                e
                            );
                            continue;
                        }
                    };

                    // Check if this autoinstall entry should be the default
                    if let (Some(default_iso), Some(default_script)) =
                        (&interface.default_iso, &interface.default_script)
                    {
                        if !default_script.is_empty() && default_iso == &iso_info.file_name && default_script == &script.name {
                            default_position = Some(position);
                        }
                    }

                    builder.add_entry(entry);
                    position += 1;
                }
            }
        }

        if let Some(pos) = default_position {
            builder.set_default(pos);
        }

        let grub_cfg = builder.build()?;

        // Write to TFTP directory -- an interface-level `tftp_root` override
        // takes precedence over the global one, so this must match whatever
        // directory the Nix side's TFTP server/file-staging actually use for
        // this interface.
        let tftp_root = interface.tftp_root.as_ref().unwrap_or(&self.config.tftp_root);
        let grub_dir = tftp_root.join(interface.id.to_string()).join("grub");

        tokio::fs::create_dir_all(&grub_dir)
            .await
            .map_err(|source| PxeBootError::GrubWrite {
                path: grub_dir.clone(),
                source,
            })?;

        let grub_cfg_path = grub_dir.join("grub.cfg");
        tokio::fs::write(&grub_cfg_path, grub_cfg)
            .await
            .map_err(|source| PxeBootError::GrubWrite {
                path: grub_cfg_path,
                source,
            })?;

        tracing::info!(
            "Generated GRUB menu for interface {} (ID: {}) with {} entries",
            interface.name,
            interface.id,
            position
        );

        Ok(())
    }

    /// Cleanup: unmount all ISOs
    pub async fn cleanup(&self) -> Result<()> {
        tracing::info!("Cleaning up mounted ISOs");
        self.iso_mounter.unmount_all().await?;
        tracing::info!("Cleanup complete");
        Ok(())
    }

    /// List discovered ISOs
    pub async fn list_isos(&self) -> Result<Vec<std::path::PathBuf>> {
        self.iso_discovery.discover().await
    }

    /// Post-hoc diagnostic report: for each discovered ISO, actually run
    /// distro detection (reusing already-mounted ISOs from a prior
    /// `prepare()` run where possible -- `IsoMounter::mount` is a no-op
    /// in that case) and report what would end up in the GRUB menu,
    /// instead of just the raw filenames `list_isos` returns. Read-only:
    /// never writes a GRUB menu or touches autoinstall seeds. Intended
    /// for an operator debugging "why isn't my ISO showing up" after the
    /// fact, not a pre-run preview (`prepare()`'s steps are all
    /// idempotent, so there's no destructive action to preview away from
    /// in the first place).
    pub async fn status(&self) -> Result<Vec<IsoStatus>> {
        let iso_paths = self.iso_discovery.discover().await?;
        let mut report = Vec::with_capacity(iso_paths.len());

        for iso_path in &iso_paths {
            let Some(file_name) = iso_path.file_name() else {
                continue;
            };
            let file_name = file_name.to_string_lossy().to_string();

            let mount_path = match self.iso_mounter.mount(iso_path).await {
                Ok(path) => path,
                Err(e) => {
                    report.push(IsoStatus {
                        file_name,
                        distro: None,
                        menu_entries: 0,
                        error: Some(format!("failed to mount: {e}")),
                    });
                    continue;
                }
            };

            let detector = match self.detector_registry.detect(&mount_path).await {
                Ok(detector) => detector,
                Err(e) => {
                    report.push(IsoStatus {
                        file_name,
                        distro: None,
                        menu_entries: 0,
                        error: Some(format!("failed to detect distribution: {e}")),
                    });
                    continue;
                }
            };

            let mut iso_info =
                IsoInfo::placeholder(file_name.clone(), iso_path.clone(), mount_path.clone());

            match detector.extract_boot_info(&iso_info).await {
                Ok(boot_info) => {
                    iso_info.apply_boot_info(&boot_info);
                    // Base entry + one per configured autoinstall script
                    // for this ISO -- mirrors generate_grub_menu's own
                    // entry count exactly, without needing to actually
                    // build any GRUB entries.
                    let autoinstall_entries = self
                        .config
                        .autoinstall
                        .get(&file_name)
                        .map(|scripts| scripts.len())
                        .unwrap_or(0);
                    report.push(IsoStatus {
                        file_name,
                        distro: Some(format!("{:?}", boot_info.distro_type)),
                        menu_entries: 1 + autoinstall_entries,
                        error: None,
                    });
                }
                Err(e) => {
                    report.push(IsoStatus {
                        file_name,
                        distro: Some(detector.id().to_string()),
                        menu_entries: 0,
                        error: Some(format!("detected but failed to extract boot info: {e}")),
                    });
                }
            }
        }

        Ok(report)
    }
}

/// One ISO's outcome as reported by `PxeBootService::status()`.
#[derive(Debug, Clone)]
pub struct IsoStatus {
    pub file_name: String,
    /// `None` only when mounting or detection itself failed outright
    /// (not even the `unknown` fallback detector result).
    pub distro: Option<String>,
    /// How many GRUB menu entries this ISO would contribute (base entry
    /// + one per configured autoinstall script); `0` if it errored.
    pub menu_entries: usize,
    pub error: Option<String>,
}

/// Soft-validates each interface's `default_iso`/`default_script` against
/// what was actually discovered, returning one warning string per
/// mismatch (empty if everything lines up). A mismatch is never fatal --
/// the configured default simply never takes effect -- but it's easy to
/// typo an ISO filename or script name in the Nix config, so it's worth
/// surfacing. Pulled out of `prepare()` as a pure function so this logic
/// is unit-testable without building a whole `PxeBootService`.
fn check_default_entry_warnings(
    dhcp_interfaces: &[DhcpInterface],
    discovered_iso_names: &std::collections::HashSet<String>,
    autoinstall: &std::collections::HashMap<String, Vec<AutoinstallScript>>,
) -> Vec<String> {
    let mut warnings = Vec::new();

    for interface in dhcp_interfaces {
        let Some(default_iso) = &interface.default_iso else {
            continue;
        };

        if !discovered_iso_names.contains(default_iso) {
            warnings.push(format!(
                "Interface {} (ID: {}): default_iso '{}' does not match any discovered ISO -- it will have no effect.",
                interface.name, interface.id, default_iso
            ));
            continue;
        }

        let Some(default_script) = &interface.default_script else {
            continue;
        };
        if default_script.is_empty() {
            continue;
        }

        let script_known = autoinstall
            .get(default_iso)
            .map(|scripts| scripts.iter().any(|s| &s.name == default_script))
            .unwrap_or(false);
        if !script_known {
            warnings.push(format!(
                "Interface {} (ID: {}): default_script '{}' does not match any autoinstall script for ISO '{}' -- it will have no effect.",
                interface.name, interface.id, default_script, default_iso
            ));
        }
    }

    warnings
}

#[cfg(test)]
mod tests {
    use super::*;
    use config::HttpConfig;
    use distro::unknown::UnknownDetector;
    use std::collections::HashMap;

    fn config_with(tftp_root: &std::path::Path, runtime_root: &std::path::Path) -> PxeBootConfig {
        PxeBootConfig {
            iso_folder_path: std::path::PathBuf::from("/data/iso"),
            tftp_root: tftp_root.to_path_buf(),
            runtime_root: runtime_root.to_path_buf(),
            dhcp_interfaces: vec![],
            autoinstall: HashMap::new(),
            http: HttpConfig { port: 1337 },
        }
    }

    fn interface(id: u32, tftp_root: Option<std::path::PathBuf>) -> DhcpInterface {
        DhcpInterface {
            id,
            name: "eth0".to_string(),
            gateway: "192.168.1.1".parse().unwrap(),
            default_iso: None,
            default_script: None,
            tftp_root,
        }
    }

    /// `valid=false` produces a kernel/initrd path that is NOT under
    /// `mount_path`, which makes `MenuEntryFactory::create_entry`'s
    /// `strip_prefix` fail -- the same failure mode the per-entry
    /// isolation in `generate_grub_menu` is meant to contain.
    fn iso_info_and_boot(
        mount_path: &std::path::Path,
        valid: bool,
        file_name: &str,
    ) -> (IsoInfo, BootInfo) {
        let (kernel_path, initrd_path) = if valid {
            (mount_path.join("boot/vmlinuz"), mount_path.join("boot/initrd"))
        } else {
            (
                std::path::PathBuf::from("/totally/unrelated/vmlinuz"),
                std::path::PathBuf::from("/totally/unrelated/initrd"),
            )
        };

        let iso_info = IsoInfo {
            file_name: file_name.to_string(),
            file_path: mount_path.join(file_name),
            mount_path: mount_path.to_path_buf(),
            distro_type: DistroType::NixOS,
            kernel_path: kernel_path.clone(),
            initrd_path: initrd_path.clone(),
        };
        let boot_info = BootInfo {
            kernel_path,
            initrd_path,
            distro_type: DistroType::NixOS,
            version: None,
            architecture: Some("x86_64".to_string()),
            init_path: None,
        };
        (iso_info, boot_info)
    }

    #[tokio::test]
    async fn grub_cfg_written_under_global_tftp_root_by_default() {
        let rt = tempfile::tempdir().unwrap();
        let global_root = rt.path().join("global");
        let config = config_with(&global_root, rt.path());
        let service = PxeBootService::new(config);

        service
            .generate_grub_menu(&interface(7, None), &[])
            .await
            .unwrap();

        assert!(global_root.join("7").join("grub").join("grub.cfg").exists());
    }

    #[tokio::test]
    async fn per_interface_tftp_root_override_takes_precedence() {
        let rt = tempfile::tempdir().unwrap();
        let global_root = rt.path().join("global");
        let override_root = rt.path().join("override");
        let config = config_with(&global_root, rt.path());
        let service = PxeBootService::new(config);

        service
            .generate_grub_menu(&interface(7, Some(override_root.clone())), &[])
            .await
            .unwrap();

        assert!(override_root.join("7").join("grub").join("grub.cfg").exists());
        assert!(!global_root.join("7").join("grub").join("grub.cfg").exists());
    }

    #[tokio::test]
    async fn one_bad_entry_does_not_drop_other_entries_from_menu() {
        let rt = tempfile::tempdir().unwrap();
        let global_root = rt.path().join("global");
        let config = config_with(&global_root, rt.path());
        let service = PxeBootService::new(config);

        let mount_path = rt.path().join("mnt");
        let (bad_iso, bad_boot) = iso_info_and_boot(&mount_path, false, "bad.iso");
        let (good_iso, good_boot) = iso_info_and_boot(&mount_path, true, "good.iso");
        let bad_detector: Box<dyn DistroDetector> = Box::new(UnknownDetector::new());
        let good_detector: Box<dyn DistroDetector> = Box::new(UnknownDetector::new());

        let iso_infos: Vec<(IsoInfo, BootInfo, &dyn DistroDetector)> = vec![
            (bad_iso, bad_boot, bad_detector.as_ref()),
            (good_iso, good_boot, good_detector.as_ref()),
        ];

        service
            .generate_grub_menu(&interface(7, None), &iso_infos, &[])
            .await
            .unwrap();

        let grub_cfg = tokio::fs::read_to_string(
            global_root.join("7").join("grub").join("grub.cfg"),
        )
        .await
        .unwrap();

        assert!(grub_cfg.contains("good.iso"));
        assert!(!grub_cfg.contains("bad.iso"));
    }

    #[tokio::test]
    async fn failed_interface_does_not_affect_other_interfaces() {
        let rt = tempfile::tempdir().unwrap();
        let global_root = rt.path().join("global");
        let config = config_with(&global_root, rt.path());
        let service = PxeBootService::new(config);

        // A "tftp_root" that's actually a regular file, not a directory --
        // create_dir_all underneath it fails with ENOTDIR, simulating a
        // broken per-interface override.
        let bad_root = rt.path().join("not-a-directory");
        tokio::fs::write(&bad_root, b"I am a file, not a directory")
            .await
            .unwrap();

        let bad_result = service
            .generate_grub_menu(&interface(1, Some(bad_root)), &[], &[])
            .await;
        assert!(bad_result.is_err());

        // A subsequent, independent interface must still succeed -- this
        // is exactly the property `prepare()`'s `if let Err(e) = ... {
        // warn }` (no `?`) around this call protects.
        service
            .generate_grub_menu(&interface(2, None), &[], &[])
            .await
            .unwrap();

        assert!(global_root.join("2").join("grub").join("grub.cfg").exists());
    }

    fn interface_with_default(
        id: u32,
        default_iso: Option<&str>,
        default_script: Option<&str>,
    ) -> DhcpInterface {
        DhcpInterface {
            id,
            name: "eth0".to_string(),
            gateway: "192.168.1.1".parse().unwrap(),
            default_iso: default_iso.map(|s| s.to_string()),
            default_script: default_script.map(|s| s.to_string()),
            tftp_root: None,
        }
    }

    fn known_isos(names: &[&str]) -> std::collections::HashSet<String> {
        names.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn no_warning_when_no_default_iso_configured() {
        let interfaces = [interface_with_default(1, None, None)];
        let warnings =
            check_default_entry_warnings(&interfaces, &known_isos(&[]), &HashMap::new());
        assert!(warnings.is_empty());
    }

    #[test]
    fn no_warning_when_default_iso_matches_and_no_script_configured() {
        let interfaces = [interface_with_default(1, Some("nixos.iso"), None)];
        let warnings = check_default_entry_warnings(
            &interfaces,
            &known_isos(&["nixos.iso"]),
            &HashMap::new(),
        );
        assert!(warnings.is_empty());
    }

    #[test]
    fn warns_when_default_iso_does_not_match_any_discovered_iso() {
        let interfaces = [interface_with_default(1, Some("typo.iso"), None)];
        let warnings = check_default_entry_warnings(
            &interfaces,
            &known_isos(&["nixos.iso"]),
            &HashMap::new(),
        );
        assert_eq!(warnings.len(), 1);
        assert!(warnings[0].contains("typo.iso"));
        assert!(warnings[0].contains("does not match any discovered ISO"));
    }

    #[test]
    fn no_warning_when_default_script_is_empty_string() {
        // An empty default_script means "no script" (the base entry is
        // the default), not "a script named ''".
        let interfaces = [interface_with_default(1, Some("ubuntu.iso"), Some(""))];
        let warnings = check_default_entry_warnings(
            &interfaces,
            &known_isos(&["ubuntu.iso"]),
            &HashMap::new(),
        );
        assert!(warnings.is_empty());
    }

    #[test]
    fn warns_when_default_script_does_not_match_any_autoinstall_script() {
        let interfaces = [interface_with_default(
            1,
            Some("ubuntu.iso"),
            Some("typo.ks"),
        )];
        let mut autoinstall = HashMap::new();
        autoinstall.insert(
            "ubuntu.iso".to_string(),
            vec![AutoinstallScript {
                name: "minimal.ks".to_string(),
                script_path: std::path::PathBuf::from("/nix/store/xxx-minimal.ks"),
            }],
        );

        let warnings =
            check_default_entry_warnings(&interfaces, &known_isos(&["ubuntu.iso"]), &autoinstall);
        assert_eq!(warnings.len(), 1);
        assert!(warnings[0].contains("typo.ks"));
        assert!(warnings[0].contains("ubuntu.iso"));
    }

    #[test]
    fn no_warning_when_default_script_matches_a_real_autoinstall_script() {
        let interfaces = [interface_with_default(
            1,
            Some("ubuntu.iso"),
            Some("minimal.ks"),
        )];
        let mut autoinstall = HashMap::new();
        autoinstall.insert(
            "ubuntu.iso".to_string(),
            vec![AutoinstallScript {
                name: "minimal.ks".to_string(),
                script_path: std::path::PathBuf::from("/nix/store/xxx-minimal.ks"),
            }],
        );

        let warnings =
            check_default_entry_warnings(&interfaces, &known_isos(&["ubuntu.iso"]), &autoinstall);
        assert!(warnings.is_empty());
    }

    #[test]
    fn does_not_check_default_script_when_default_iso_itself_is_unknown() {
        // Only one warning expected here, not two -- a typo'd default_iso
        // already explains why nothing takes effect; piling on a second
        // warning about the script too would just be noise.
        let interfaces = [interface_with_default(
            1,
            Some("typo.iso"),
            Some("minimal.ks"),
        )];
        let warnings =
            check_default_entry_warnings(&interfaces, &known_isos(&["ubuntu.iso"]), &HashMap::new());
        assert_eq!(warnings.len(), 1);
        assert!(warnings[0].contains("default_iso"));
    }

    #[tokio::test]
    async fn status_reports_a_discovered_iso_that_fails_to_mount() {
        // Mounting a real ISO requires CAP_SYS_ADMIN -- this test runs
        // unprivileged (same as any non-root CI sandbox), so the real
        // `mount` command deterministically fails regardless of the
        // file's actual content, exercising status()'s error-reporting
        // path without needing root or a real loop device.
        let rt = tempfile::tempdir().unwrap();
        let iso_dir = tempfile::tempdir().unwrap();
        let fake_iso = iso_dir.path().join("test.iso");
        tokio::fs::write(&fake_iso, b"not a real iso")
            .await
            .unwrap();

        let mut config = config_with(rt.path(), rt.path());
        config.iso_folder_paths = vec![iso_dir.path().to_path_buf()];
        let service = PxeBootService::new(config);

        let report = service.status().await.unwrap();

        assert_eq!(report.len(), 1);
        assert_eq!(report[0].file_name, "test.iso");
        assert_eq!(report[0].menu_entries, 0);
        assert!(report[0].error.is_some());
        let error = report[0].error.as_ref().unwrap();
        assert!(error.contains("failed to mount"));
        // A3 regression: the real `mount` command's own stderr (not just
        // a generic "exited with <status>") must reach this error --
        // `do_mount` previously used `.status()`, which discarded stderr
        // entirely (it only ever reached the systemd journal via fd
        // inheritance, invisible to this programmatic error path).
        //
        // Asserting on "mount:" (not a specific denial reason like
        // "Permission denied") is deliberate: the EXACT failure mode is
        // environment-dependent -- an interactive unprivileged shell saw
        // "mount failed: Permission denied.", while the Nix build
        // sandbox saw "failed to set up loop device for ..." instead
        // (no /dev/loop* access at all, a different restriction than
        // plain CAP_SYS_ADMIN denial) -- but util-linux's `mount(8)`
        // always prefixes its OWN diagnostic output with "mount:",
        // regardless of which restriction tripped, so that prefix is
        // the one environment-agnostic thing to check for.
        assert!(
            error.contains("mount:"),
            "error should include mount's own stderr text (prefixed \"mount:\"), got: {error}"
        );
    }

    #[tokio::test]
    async fn status_reports_empty_when_no_isos_discovered() {
        let rt = tempfile::tempdir().unwrap();
        let iso_dir = tempfile::tempdir().unwrap();

        let mut config = config_with(rt.path(), rt.path());
        config.iso_folder_paths = vec![iso_dir.path().to_path_buf()];
        let service = PxeBootService::new(config);

        let report = service.status().await.unwrap();

        assert!(report.is_empty());
    }

}
