pub mod autoinstall;
pub mod config;
pub mod distro;
pub mod error;
pub mod grub;
pub mod iso;

use autoinstall::{AutoinstallManager, AutoinstallPreparing};
use config::{AutoinstallScript, BootInfo, DhcpInterface, DistroType, IsoInfo, MenuEntry, PxeBootConfig};
use distro::{DetectorRegistry, DistroDetector};
use error::{IoResultExt, PxeBootError, Result};
use fs4::tokio::AsyncFileExt;
use grub::{GrubMenuBuilder, MenuEntryFactory};
use iso::{IsoDiscovery, IsoDiscovering, IsoMounter, IsoMounting, ServeTree, ServeTreeRebuilding};
use std::path::Path;

/// Acquires an exclusive, non-blocking lock on `<runtime_root>/.prepare.lock`
/// (D38) -- held for the duration of `prepare()` via the returned `File`
/// (released automatically when it's dropped, or by the OS if the
/// process crashes). Prevents two concurrent `prepare()` invocations
/// (e.g. an operator's manual CLI run racing the systemd service's own
/// instance, or a `systemctl restart` landing mid-run) from mounting/
/// unmounting/rewriting the same ISOs and GRUB configs at the same
/// time -- confirmed elsewhere in this file that even just concurrent
/// ISO *mounts* alone hit a real kernel-level loop-device race (see
/// `prepare()`'s own sequential-mounting comment); racing two FULL
/// `prepare()` runs would be considerably worse.
///
/// Fails fast (does not block waiting for the other run to finish) --
/// matches this codebase's existing fail-fast-and-report posture rather
/// than silently queuing.
async fn acquire_prepare_lock(runtime_root: &Path) -> Result<tokio::fs::File> {
    let lock_path = runtime_root.join(".prepare.lock");
    let file = tokio::fs::OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .open(&lock_path)
        .await
        .with_path(&lock_path)?;

    file.try_lock().map_err(|_| {
        PxeBootError::Config(format!(
            "another 'pxe-boot-prepare prepare' run is already in progress \
             (lock held on {})",
            lock_path.display()
        ))
    })?;

    Ok(file)
}

pub struct PxeBootService {
    config: PxeBootConfig,
    detector_registry: DetectorRegistry,
    iso_discovery: Box<dyn IsoDiscovering>,
    iso_mounter: Box<dyn IsoMounting>,
    iso_serve_tree: Box<dyn ServeTreeRebuilding>,
    autoinstall_manager: Box<dyn AutoinstallPreparing>,
}

impl PxeBootService {
    pub fn new(config: PxeBootConfig) -> Self {
        let detector_registry = DetectorRegistry::new();
        let iso_discovery = IsoDiscovery::new(config.iso_folder_paths.clone());
        let iso_mounter = IsoMounter::new(config.runtime_root.clone());
        let iso_serve_tree = ServeTree::new(config.runtime_root.clone());
        let autoinstall_manager = AutoinstallManager::new(config.runtime_root.clone());

        Self::new_with_dependencies(
            config,
            detector_registry,
            Box::new(iso_discovery),
            Box::new(iso_mounter),
            Box::new(iso_serve_tree),
            Box::new(autoinstall_manager),
        )
    }

    /// Fully-injectable constructor (C33) -- lets tests substitute a
    /// `Fake*` for any collaborator while keeping real ones for the rest,
    /// to get deterministic, fast coverage of `prepare()`/`status()`
    /// orchestration that real I/O can't easily produce (e.g. partial
    /// mount failure across multiple ISOs, or an autoinstall-write
    /// failure in isolation). `new()` above is the normal production
    /// entry point and just wires up the real collaborators through this.
    pub fn new_with_dependencies(
        config: PxeBootConfig,
        detector_registry: DetectorRegistry,
        iso_discovery: Box<dyn IsoDiscovering>,
        iso_mounter: Box<dyn IsoMounting>,
        iso_serve_tree: Box<dyn ServeTreeRebuilding>,
        autoinstall_manager: Box<dyn AutoinstallPreparing>,
    ) -> Self {
        Self {
            config,
            detector_registry,
            iso_discovery,
            iso_mounter,
            iso_serve_tree,
            autoinstall_manager,
        }
    }

    /// Main entry point: prepare PXE boot environment
    pub async fn prepare(&self) -> Result<()> {
        // D38: held for the rest of this function's scope.
        let _lock = acquire_prepare_lock(&self.config.runtime_root).await?;

        tracing::info!("Starting PXE boot preparation");

        // 1. Discover ISOs
        let iso_paths = self.iso_discovery.discover().await?;
        tracing::info!("Discovered {} ISO files", iso_paths.len());

        if iso_paths.is_empty() {
            tracing::warn!(
                "No ISO files found in {}",
                self.config
                    .iso_folder_paths
                    .iter()
                    .map(|p| p.display().to_string())
                    .collect::<Vec<_>>()
                    .join(", ")
            );
            return Ok(());
        }

        // Rebuild the canonical raw-ISO serving directory from the full
        // set of discovered ISOs -- independent of mount/detection
        // success below, since a raw whole-file download (e.g. Ubuntu's
        // `url=` fetch) doesn't need this router to have mounted the ISO
        // at all. A failure here (e.g. the runtime_root filesystem is
        // briefly unwritable) must not abort every other step of
        // preparation -- mounting/detection/menu generation below are
        // all independently useful even if raw-ISO serving is degraded.
        if let Err(e) = self.iso_serve_tree.rebuild(&iso_paths).await {
            tracing::warn!(
                "Failed to rebuild raw-ISO serving tree: {}. Whole-ISO downloads (e.g. Ubuntu's url= fetch) will be unavailable until the next successful run.",
                e
            );
        }

        // 2. Mount all ISOs, skipping failures.
        //
        // Sequential, not concurrent: `mount -t iso9660 -o loop` relies
        // on the kernel/util-linux to auto-select a free loop device
        // (no pre-reserved device number) -- a well-known TOCTOU race
        // when invoked concurrently across multiple `mount` processes
        // (two mounts can both see the same device as "free" and race
        // to attach to it). Confirmed empirically: a 4th concurrent
        // mount (added for the findiso-download-failure-path E2E fixture,
        // see tests/pxe-boot/default.nix) reproduced cross-contaminated
        // mount content that 3 concurrent mounts never had. Mounting is a
        // once-per-prepare()-run operation, not a hot path -- the lost
        // parallelism is not a meaningful cost for correctness.
        let mut mounted_isos = Vec::new();
        for path in &iso_paths {
            match self.iso_mounter.mount(path).await {
                Ok(mount_path) => {
                    mounted_isos.push((path.clone(), mount_path));
                }
                Err(e) => {
                    tracing::warn!(
                        "Failed to mount {}: {}. Skipping this ISO.",
                        path.display(),
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
        // D41: (file_name, reason) for ISOs that mounted fine but could
        // not be prepared for boot -- rendered as a loud, clearly-
        // labeled placeholder GRUB entry (see generate_grub_menu) instead
        // of silently vanishing from the menu with no operator-visible
        // signal beyond the tracing::warn! lines below.
        let mut failed_isos: Vec<(String, String)> = Vec::new();

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
                            failed_isos.push((file_name, e.to_string()));
                        }
                    }
                }
                Err(e) => {
                    tracing::warn!(
                        "Failed to detect distribution type for {}: {}. Skipping this ISO.",
                        file_name,
                        e
                    );
                    failed_isos.push((file_name, e.to_string()));
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
        failed_isos: &[(String, String)],
    ) -> Result<()> {
        let factory = MenuEntryFactory::new(interface.gateway, self.config.http.port);

        // Built once, then reused for both the interface's own grub.cfg
        // and any per-MAC override (D35) -- the menu CONTENT never
        // differs, only which position `set default=N` points at.
        let mut entries: Vec<(MenuEntry, String, Option<String>)> = Vec::new();
        let mut position = 0;

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

            entries.push((entry, iso_info.file_name.clone(), None));
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

                    entries.push((entry, iso_info.file_name.clone(), Some(script.name.clone())));
                    position += 1;
                }
            }
        }

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
        self.write_grub_cfg(
            &grub_cfg_path,
            &entries,
            failed_isos,
            interface.default_iso.as_deref(),
            interface.default_script.as_deref(),
        )
        .await?;

        // D35: one override file per reservation that configured its own
        // default -- same entries/placeholders, only `set default=N`
        // differs. GRUB's generated grub.cfg (see grub/menu.rs) tests
        // for `grub.cfg-override-${net_default_mac}` right after
        // net_bootp and `configfile`s into it when present, falling
        // through to this interface's own default otherwise.
        for reservation in &interface.reservations {
            // Nothing configured on this reservation -- nothing to
            // override (the Nix side already omits these, but guard
            // directly here too for anything constructing config JSON
            // by hand).
            if reservation.default_iso.is_none() && reservation.default_script.is_none() {
                continue;
            }

            let default_iso = reservation
                .default_iso
                .as_deref()
                .or(interface.default_iso.as_deref());
            let default_script = reservation
                .default_script
                .as_deref()
                .or(interface.default_script.as_deref());

            let override_path = grub_dir.join(format!(
                "grub.cfg-override-{}",
                reservation.mac.to_lowercase()
            ));
            self.write_grub_cfg(
                &override_path,
                &entries,
                failed_isos,
                default_iso,
                default_script,
            )
            .await?;
        }

        tracing::info!(
            "Generated GRUB menu for interface {} (ID: {}) with {} entries ({} per-MAC overrides)",
            interface.name,
            interface.id,
            position,
            interface.reservations.len()
        );

        Ok(())
    }

    /// Renders and writes one grub.cfg variant (the interface's own, or
    /// a per-MAC override, D35) from an already-built entry list --
    /// shared so the two variants can never drift in content, only in
    /// which entry is default.
    async fn write_grub_cfg(
        &self,
        path: &Path,
        entries: &[(MenuEntry, String, Option<String>)],
        failed_isos: &[(String, String)],
        default_iso: Option<&str>,
        default_script: Option<&str>,
    ) -> Result<()> {
        let mut builder = GrubMenuBuilder::new()?;

        for (entry, _, _) in entries {
            builder.add_entry(entry.clone());
        }

        if let Some(pos) = resolve_default_position(entries, default_iso, default_script) {
            builder.set_default(pos);
        }

        // D41: every interface's menu shows the same set of failed ISOs
        // -- detection/extraction happens once, globally, not per
        // interface (unlike the real bootable entries above, which ARE
        // per-interface since their URLs embed this interface's own
        // gateway).
        for (file_name, reason) in failed_isos {
            builder.add_placeholder_entry(file_name, reason);
        }

        let grub_cfg = builder.build()?;

        tokio::fs::write(path, grub_cfg)
            .await
            .map_err(|source| PxeBootError::GrubWrite {
                path: path.to_path_buf(),
                source,
            })?;

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

/// Finds the menu position matching a (default_iso, default_script)
/// pair -- shared between the interface-level default and any per-MAC
/// override (D35), so both apply the exact same matching rule: an
/// absent or empty `default_script` means "the base entry" (no
/// autoinstall), never a script literally named `""`.
fn resolve_default_position(
    entries: &[(MenuEntry, String, Option<String>)],
    default_iso: Option<&str>,
    default_script: Option<&str>,
) -> Option<usize> {
    let default_iso = default_iso?;
    let script_is_empty = default_script.map(|s| s.is_empty()).unwrap_or(true);

    entries.iter().find_map(|(entry, iso_name, script_name)| {
        if iso_name != default_iso {
            return None;
        }
        let matches = if script_is_empty {
            script_name.is_none()
        } else {
            script_name.as_deref() == default_script
        };
        matches.then_some(entry.position)
    })
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
        push_default_pair_warnings(
            &mut warnings,
            &format!("Interface {} (ID: {})", interface.name, interface.id),
            interface.default_iso.as_deref(),
            interface.default_script.as_deref(),
            discovered_iso_names,
            autoinstall,
        );

        // D35: same validation, per reservation that actually configures
        // its own override -- effective values fall back to the
        // interface's own default per-field, mirroring the precedence
        // `generate_grub_menu` applies when it builds the override file.
        // Skipping reservations with neither field set avoids re-warning
        // about the interface's own default once per uninvolved
        // reservation.
        for reservation in &interface.reservations {
            if reservation.default_iso.is_none() && reservation.default_script.is_none() {
                continue;
            }

            let default_iso = reservation
                .default_iso
                .as_deref()
                .or(interface.default_iso.as_deref());
            let default_script = reservation
                .default_script
                .as_deref()
                .or(interface.default_script.as_deref());

            push_default_pair_warnings(
                &mut warnings,
                &format!(
                    "Interface {} (ID: {}), reservation {}",
                    interface.name, interface.id, reservation.mac
                ),
                default_iso,
                default_script,
                discovered_iso_names,
                autoinstall,
            );
        }
    }

    warnings
}

fn push_default_pair_warnings(
    warnings: &mut Vec<String>,
    label: &str,
    default_iso: Option<&str>,
    default_script: Option<&str>,
    discovered_iso_names: &std::collections::HashSet<String>,
    autoinstall: &std::collections::HashMap<String, Vec<AutoinstallScript>>,
) {
    let Some(default_iso) = default_iso else {
        return;
    };

    if !discovered_iso_names.contains(default_iso) {
        warnings.push(format!(
            "{label}: default_iso '{default_iso}' does not match any discovered ISO -- it will have no effect."
        ));
        return;
    }

    let Some(default_script) = default_script else {
        return;
    };
    if default_script.is_empty() {
        return;
    }

    let script_known = autoinstall
        .get(default_iso)
        .map(|scripts| scripts.iter().any(|s| s.name == default_script))
        .unwrap_or(false);
    if !script_known {
        warnings.push(format!(
            "{label}: default_script '{default_script}' does not match any autoinstall script for ISO '{default_iso}' -- it will have no effect."
        ));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use config::{HttpConfig, ReservationOverride};
    use distro::unknown::UnknownDetector;
    use std::collections::HashMap;

    #[tokio::test]
    async fn acquire_prepare_lock_succeeds_when_uncontended() {
        let rt = tempfile::tempdir().unwrap();

        let _lock = acquire_prepare_lock(rt.path()).await.unwrap();

        assert!(rt.path().join(".prepare.lock").exists());
    }

    #[tokio::test]
    async fn acquire_prepare_lock_fails_fast_when_already_held() {
        // D38: a second concurrent attempt must not block (the whole
        // point is to fail fast and report, not hang waiting for the
        // first run to finish).
        let rt = tempfile::tempdir().unwrap();

        let _first_lock = acquire_prepare_lock(rt.path()).await.unwrap();
        let second_attempt = acquire_prepare_lock(rt.path()).await;

        assert!(second_attempt.is_err());
        let err = second_attempt.unwrap_err().to_string();
        assert!(
            err.contains("already in progress"),
            "error should explain the lock contention, got: {err}"
        );
    }

    #[tokio::test]
    async fn acquire_prepare_lock_succeeds_again_after_the_first_is_released() {
        let rt = tempfile::tempdir().unwrap();

        {
            let _lock = acquire_prepare_lock(rt.path()).await.unwrap();
            // Dropped at the end of this block -- the OS releases the
            // flock automatically.
        }

        let second_lock = acquire_prepare_lock(rt.path()).await;
        assert!(second_lock.is_ok());
    }

    fn config_with(tftp_root: &std::path::Path, runtime_root: &std::path::Path) -> PxeBootConfig {
        PxeBootConfig {
            iso_folder_paths: vec![std::path::PathBuf::from("/data/iso")],
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
            reservations: Vec::new(),
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
            .generate_grub_menu(&interface(7, None), &[], &[])
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
            .generate_grub_menu(&interface(7, Some(override_root.clone())), &[], &[])
            .await
            .unwrap();

        assert!(override_root.join("7").join("grub").join("grub.cfg").exists());
        assert!(!global_root.join("7").join("grub").join("grub.cfg").exists());
    }

    #[tokio::test]
    async fn per_mac_override_gets_same_entries_but_a_different_default() {
        let rt = tempfile::tempdir().unwrap();
        let global_root = rt.path().join("global");
        let config = config_with(&global_root, rt.path());
        let service = PxeBootService::new(config);

        let mount_path = rt.path().join("mnt");
        let (alpha_iso, alpha_boot) = iso_info_and_boot(&mount_path, true, "alpha.iso");
        let (beta_iso, beta_boot) = iso_info_and_boot(&mount_path, true, "beta.iso");
        let detector: Box<dyn DistroDetector> = Box::new(UnknownDetector::new());

        let iso_infos: Vec<(IsoInfo, BootInfo, &dyn DistroDetector)> = vec![
            (alpha_iso, alpha_boot, detector.as_ref()),
            (beta_iso, beta_boot, detector.as_ref()),
        ];

        let mut iface = interface(7, None);
        iface.default_iso = Some("alpha.iso".to_string());
        // Uppercase on purpose -- the override filename must still come
        // out lowercase to match GRUB's own ${net_default_mac} format.
        iface.reservations = vec![ReservationOverride {
            mac: "AA:BB:CC:DD:EE:FF".to_string(),
            default_iso: Some("beta.iso".to_string()),
            default_script: None,
        }];

        service
            .generate_grub_menu(&iface, &iso_infos, &[])
            .await
            .unwrap();

        let grub_dir = global_root.join("7").join("grub");
        let base_cfg = std::fs::read_to_string(grub_dir.join("grub.cfg")).unwrap();
        let override_path = grub_dir.join("grub.cfg-override-aa:bb:cc:dd:ee:ff");
        let override_cfg = std::fs::read_to_string(&override_path).unwrap();

        // Same menu content in both...
        for cfg in [&base_cfg, &override_cfg] {
            assert!(cfg.contains("alpha.iso"));
            assert!(cfg.contains("beta.iso"));
        }
        // ...only the default differs: alpha is entry 0, beta is entry 1.
        assert!(base_cfg.contains("\nset default=0\n"));
        assert!(override_cfg.contains("\nset default=1\n"));
    }

    #[tokio::test]
    async fn reservation_with_neither_field_set_produces_no_override_file() {
        let rt = tempfile::tempdir().unwrap();
        let global_root = rt.path().join("global");
        let config = config_with(&global_root, rt.path());
        let service = PxeBootService::new(config);

        let mut iface = interface(7, None);
        iface.reservations = vec![ReservationOverride {
            mac: "00:11:22:33:44:55".to_string(),
            default_iso: None,
            default_script: None,
        }];

        service
            .generate_grub_menu(&iface, &[], &[])
            .await
            .unwrap();

        let grub_dir = global_root.join("7").join("grub");
        assert!(grub_dir.join("grub.cfg").exists());
        // Nothing configured on this reservation -- nothing to write.
        assert!(!grub_dir.join("grub.cfg-override-00:11:22:33:44:55").exists());
    }

    #[tokio::test]
    async fn reservation_override_falls_back_to_interface_default_script() {
        // A reservation that sets only `default_iso` inherits the
        // interface's own `default_script` for that field -- per-field
        // override, not all-or-nothing (D35).
        let rt = tempfile::tempdir().unwrap();
        let global_root = rt.path().join("global");
        let mut autoinstall = HashMap::new();
        autoinstall.insert(
            "alpha.iso".to_string(),
            vec![AutoinstallScript {
                name: "minimal.ks".to_string(),
                script_path: std::path::PathBuf::from("/nix/store/xxx-minimal.ks"),
            }],
        );
        let mut config = config_with(&global_root, rt.path());
        config.autoinstall = autoinstall;
        let service = PxeBootService::new(config);

        let mount_path = rt.path().join("mnt");
        let (alpha_iso, alpha_boot) = iso_info_and_boot(&mount_path, true, "alpha.iso");
        let detector: Box<dyn DistroDetector> = Box::new(UnknownDetector::new());
        let iso_infos: Vec<(IsoInfo, BootInfo, &dyn DistroDetector)> =
            vec![(alpha_iso, alpha_boot, detector.as_ref())];

        let mut iface = interface(7, None);
        iface.default_iso = Some("alpha.iso".to_string());
        iface.default_script = Some("minimal.ks".to_string());
        iface.reservations = vec![ReservationOverride {
            mac: "00:11:22:33:44:55".to_string(),
            default_iso: Some("alpha.iso".to_string()),
            default_script: None,
        }];

        service
            .generate_grub_menu(&iface, &iso_infos, &[])
            .await
            .unwrap();

        let grub_dir = global_root.join("7").join("grub");
        let override_cfg =
            std::fs::read_to_string(grub_dir.join("grub.cfg-override-00:11:22:33:44:55")).unwrap();

        // Entry 0 is the base alpha.iso entry, entry 1 is alpha.iso +
        // minimal.ks -- the reservation's missing default_script must
        // resolve to the interface's, landing on entry 1, not entry 0.
        assert!(override_cfg.contains("\nset default=1\n"));
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
    async fn failed_isos_get_a_placeholder_entry_in_the_menu() {
        // D41: an ISO that couldn't be prepared must still show up in
        // the menu, as a non-bootable placeholder with the reason --
        // not silently vanish with only a journal line.
        let rt = tempfile::tempdir().unwrap();
        let global_root = rt.path().join("global");
        let config = config_with(&global_root, rt.path());
        let service = PxeBootService::new(config);

        let failed_isos = vec![(
            "mystery.iso".to_string(),
            "Unknown distribution type".to_string(),
        )];

        service
            .generate_grub_menu(&interface(7, None), &[], &failed_isos)
            .await
            .unwrap();

        let grub_cfg =
            tokio::fs::read_to_string(global_root.join("7").join("grub").join("grub.cfg"))
                .await
                .unwrap();

        assert!(grub_cfg.contains("mystery.iso (unsupported)"));
        assert!(grub_cfg.contains("Unknown distribution type"));
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
            reservations: Vec::new(),
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

    #[test]
    fn warns_on_reservation_with_its_own_typo_d_default_iso() {
        let mut iface = interface_with_default(1, Some("nixos.iso"), None);
        iface.reservations = vec![ReservationOverride {
            mac: "aa:bb:cc:dd:ee:ff".to_string(),
            default_iso: Some("typo.iso".to_string()),
            default_script: None,
        }];
        let warnings =
            check_default_entry_warnings(&[iface], &known_isos(&["nixos.iso"]), &HashMap::new());

        assert_eq!(warnings.len(), 1);
        assert!(warnings[0].contains("aa:bb:cc:dd:ee:ff"));
        assert!(warnings[0].contains("typo.iso"));
    }

    #[test]
    fn reservation_inherits_interface_default_iso_for_warning_purposes() {
        // The reservation only overrides default_script -- the
        // (inherited) default_iso it resolves to is a typo, and that
        // must still be caught even though the reservation itself never
        // named it.
        let mut iface = interface_with_default(1, Some("typo.iso"), None);
        iface.reservations = vec![ReservationOverride {
            mac: "aa:bb:cc:dd:ee:ff".to_string(),
            default_iso: None,
            default_script: Some("minimal.ks".to_string()),
        }];
        let warnings =
            check_default_entry_warnings(&[iface], &known_isos(&["nixos.iso"]), &HashMap::new());

        // One for the interface's own default_iso, one for the
        // reservation inheriting that same bad value.
        assert_eq!(warnings.len(), 2);
        assert!(warnings.iter().any(|w| w.contains("aa:bb:cc:dd:ee:ff")));
    }

    #[test]
    fn reservation_with_neither_field_set_produces_no_warning() {
        let mut iface = interface_with_default(1, Some("typo.iso"), None);
        iface.reservations = vec![ReservationOverride {
            mac: "aa:bb:cc:dd:ee:ff".to_string(),
            default_iso: None,
            default_script: None,
        }];
        let warnings =
            check_default_entry_warnings(&[iface], &known_isos(&["nixos.iso"]), &HashMap::new());

        // Only the interface-level warning -- the uninvolved reservation
        // must not generate a second, redundant one.
        assert_eq!(warnings.len(), 1);
        assert!(!warnings[0].contains("reservation"));
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

    // C33: the two tests below use the new DI seam (`new_with_dependencies`
    // + `Fake*` collaborators) to cover orchestration behavior the existing
    // real-I/O tests structurally can't reach -- e.g. the unprivileged
    // `mount` command above always fails the same way for every ISO, so
    // there was previously no way to get *some* ISOs to mount successfully
    // and others to fail in the same run.

    #[tokio::test]
    async fn status_reports_per_iso_results_independently_when_mounts_partially_succeed() {
        let rt = tempfile::tempdir().unwrap();
        let iso_dir = tempfile::tempdir().unwrap();
        tokio::fs::write(iso_dir.path().join("good.iso"), b"x")
            .await
            .unwrap();
        tokio::fs::write(iso_dir.path().join("bad.iso"), b"x")
            .await
            .unwrap();
        // An empty dir stands in for "good.iso"'s mount point -- no real
        // detector recognizes it, so it falls through to `UnknownDetector`
        // (always matches, see distro/detector.rs), which is enough to
        // prove mounting succeeded independent of distro detection.
        let mount_target = tempfile::tempdir().unwrap();

        let mut config = config_with(rt.path(), rt.path());
        config.iso_folder_paths = vec![iso_dir.path().to_path_buf()];

        let service = PxeBootService::new_with_dependencies(
            config,
            DetectorRegistry::new(),
            Box::new(IsoDiscovery::new(vec![iso_dir.path().to_path_buf()])),
            Box::new(
                crate::iso::mount::FakeIsoMounter::new()
                    .succeeding_for("good.iso", mount_target.path().to_path_buf())
                    .failing_for("bad.iso", "simulated mount failure"),
            ),
            Box::new(ServeTree::new(rt.path().to_path_buf())),
            Box::new(AutoinstallManager::new(rt.path().to_path_buf())),
        );

        let report = service.status().await.unwrap();

        assert_eq!(report.len(), 2);
        // An empty mount target has no real distro to find, so "good.iso"
        // still fails -- but only at the NEXT stage (boot-info extraction,
        // after `UnknownDetector` matches as the catch-all), proving it
        // got past mounting independently of "bad.iso".
        let good = report.iter().find(|r| r.file_name == "good.iso").unwrap();
        let good_error = good
            .error
            .as_ref()
            .expect("empty mount target has no real distro, so extraction should fail");
        assert!(
            good_error.contains("detected but failed to extract boot info"),
            "good.iso should mount successfully and only fail at extraction, got: {good_error}"
        );

        let bad = report.iter().find(|r| r.file_name == "bad.iso").unwrap();
        let bad_error = bad.error.as_ref().unwrap();
        assert!(bad_error.contains("failed to mount"));
        assert!(bad_error.contains("simulated mount failure"));
    }

    #[tokio::test]
    async fn prepare_still_generates_grub_menus_when_autoinstall_preparation_fails() {
        // The real AutoinstallManager only fails via filesystem-permission
        // tricks that are fiddly to set up reliably across environments --
        // a Fake makes this one-line and deterministic.
        let rt = tempfile::tempdir().unwrap();
        let global_root = rt.path().join("global");
        let mut config = config_with(&global_root, rt.path());
        config.dhcp_interfaces = vec![interface(7, None)];
        // `prepare()` returns early when no ISOs are discovered at all, so
        // at least one (mountable, even if not bootable) ISO is needed to
        // reach the autoinstall/GRUB-generation stages this test targets.
        let mount_target = tempfile::tempdir().unwrap();

        let service = PxeBootService::new_with_dependencies(
            config,
            DetectorRegistry::new(),
            Box::new(crate::iso::discovery::FakeIsoDiscovery::returning(vec![
                std::path::PathBuf::from("/fake/whatever.iso"),
            ])),
            Box::new(
                crate::iso::mount::FakeIsoMounter::new()
                    .succeeding_for("whatever.iso", mount_target.path().to_path_buf()),
            ),
            Box::new(ServeTree::new(rt.path().to_path_buf())),
            Box::new(crate::autoinstall::manager::FakeAutoinstallPreparing::failing_with(
                "simulated autoinstall failure",
            )),
        );

        service.prepare().await.unwrap();

        assert!(
            global_root.join("7").join("grub").join("grub.cfg").exists(),
            "GRUB menu generation must still run even when autoinstall preparation fails"
        );
    }
}
