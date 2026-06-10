pub mod autoinstall;
pub mod config;
pub mod distro;
pub mod error;
pub mod grub;
pub mod iso;

use autoinstall::AutoinstallManager;
use config::{BootInfo, DhcpInterface, DistroType, IsoInfo, PxeBootConfig};
use distro::{DetectorRegistry, DistroDetector};
use error::{PxeBootError, Result};
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
            let file_name = iso_path
                .file_name()
                .unwrap()
                .to_string_lossy()
                .to_string();

            // Try to detect and extract boot info, skip on failure
            match self.detector_registry.detect(mount_path).await {
                Ok(detector) => {
                    let mut iso_info = IsoInfo {
                        file_name: file_name.clone(),
                        file_path: iso_path.clone(),
                        mount_path: mount_path.clone(),
                        distro_type: DistroType::Unknown("".into()),
                        kernel_path: std::path::PathBuf::new(),
                        initrd_path: std::path::PathBuf::new(),
                    };

                    match detector.extract_boot_info(&iso_info).await {
                        Ok(boot_info) => {
                            iso_info.distro_type = boot_info.distro_type.clone();
                            iso_info.kernel_path = boot_info.kernel_path.clone();
                            iso_info.initrd_path = boot_info.initrd_path.clone();

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

        // 4. Process autoinstall scripts
        self.autoinstall_manager.prepare(&self.config).await?;

        // 5. Generate GRUB menus for each DHCP interface
        for interface in &self.config.dhcp_interfaces {
            self.generate_grub_menu(interface, &iso_infos).await?;
        }

        tracing::info!("PXE boot preparation complete");
        Ok(())
    }

    async fn generate_grub_menu(
        &self,
        interface: &DhcpInterface,
        iso_infos: &[(IsoInfo, BootInfo, &dyn DistroDetector)],
    ) -> Result<()> {
        let mut builder = GrubMenuBuilder::new();
        
        let factory = MenuEntryFactory::new(
            interface.gateway,
            self.config.http.mount_port,
            self.config.http.iso_port,
        );

        let mut position = 0;
        let mut default_position = None;

        for (iso_info, boot_info, detector) in iso_infos {
            // Base entry (no autoinstall)
            let entry = factory.create_entry(
                iso_info,
                boot_info,
                *detector,
                None,
                position,
            )?;

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
                    let entry = factory.create_entry(
                        iso_info,
                        boot_info,
                        *detector,
                        Some(script),
                        position,
                    )?;

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

        // Write to TFTP directory
        let grub_dir = self
            .config
            .tftp_root
            .join(interface.id.to_string())
            .join("grub");

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

    /// Get the ISO mounter for direct access
    pub fn iso_mounter(&self) -> &IsoMounter {
        &self.iso_mounter
    }
}
