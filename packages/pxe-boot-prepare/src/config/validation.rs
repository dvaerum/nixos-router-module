use crate::config::schema::PxeBootConfig;
use crate::error::{PxeBootError, Result};
use std::collections::HashSet;

impl PxeBootConfig {
    /// Validate the configuration
    pub fn validate(&self) -> Result<()> {
        // Validate ISO folder exists
        if !self.iso_folder_path.exists() {
            return Err(PxeBootError::Config(format!(
                "ISO folder does not exist: {}",
                self.iso_folder_path.display()
            )));
        }

        // Validate DHCP interface IDs are unique
        let mut ids = HashSet::new();
        for interface in &self.dhcp_interfaces {
            if !ids.insert(interface.id) {
                return Err(PxeBootError::Config(format!(
                    "Duplicate DHCP interface ID: {}",
                    interface.id
                )));
            }
        }

        // Validate autoinstall scripts exist
        for (iso, scripts) in &self.autoinstall {
            for script in scripts {
                if !script.script_path.exists() {
                    return Err(PxeBootError::Config(format!(
                        "Autoinstall script not found for ISO '{}': {}",
                        iso,
                        script.script_path.display()
                    )));
                }
            }
        }

        Ok(())
    }
}
