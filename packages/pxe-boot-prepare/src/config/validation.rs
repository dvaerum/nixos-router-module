use crate::config::schema::PxeBootConfig;
use crate::error::{PxeBootError, Result};
use std::collections::HashSet;

impl PxeBootConfig {
    /// Validate the configuration
    pub fn validate(&self) -> Result<()> {
        // Validate every ISO source directory exists
        for path in &self.iso_folder_paths {
            if !path.exists() {
                return Err(PxeBootError::Config(format!(
                    "ISO folder does not exist: {}",
                    path.display()
                )));
            }
        }

        // Validate TFTP root exists. Not strictly required mechanically
        // (generate_grub_menu's create_dir_all would silently create it),
        // but a missing tftp_root is far more likely to mean "the
        // intended mount/destination isn't there yet" than "please
        // auto-create a fresh directory for me" -- fail fast instead of
        // silently writing into the wrong place.
        if !self.tftp_root.exists() {
            return Err(PxeBootError::Config(format!(
                "TFTP root does not exist: {}",
                self.tftp_root.display()
            )));
        }

        // Same check, but for the PER-INTERFACE override (lib.rs uses
        // `interface.tftp_root.unwrap_or(&self.tftp_root)` at the actual
        // grub.cfg write site) -- without this, a misconfigured override
        // silently fell through to create_dir_all() creating a
        // possibly-wrong directory instead of failing fast, exactly the
        // gap the global check above exists to close.
        for interface in &self.dhcp_interfaces {
            if let Some(tftp_root) = &interface.tftp_root {
                if !tftp_root.exists() {
                    return Err(PxeBootError::Config(format!(
                        "TFTP root override for interface '{}' does not exist: {}",
                        interface.name,
                        tftp_root.display()
                    )));
                }
            }
        }

        // Same rationale as tftp_root above: a missing runtime_root
        // (where ISO mount points, the raw-ISO serve tree, and
        // autoinstall seeds all live) almost certainly means the
        // intended mount point isn't there yet, not "create a fresh
        // directory for me".
        if !self.runtime_root.exists() {
            return Err(PxeBootError::Config(format!(
                "Runtime root does not exist: {}",
                self.runtime_root.display()
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::schema::{DhcpInterface, HttpConfig};
    use std::collections::HashMap;

    fn valid_config(iso_dir: &std::path::Path, tftp_dir: &std::path::Path) -> PxeBootConfig {
        PxeBootConfig {
            iso_folder_paths: vec![iso_dir.to_path_buf()],
            tftp_root: tftp_dir.to_path_buf(),
            runtime_root: tftp_dir.to_path_buf(),
            dhcp_interfaces: vec![],
            autoinstall: HashMap::new(),
            http: HttpConfig { port: 1337 },
        }
    }

    #[test]
    fn valid_config_passes() {
        let iso_dir = tempfile::tempdir().unwrap();
        let tftp_dir = tempfile::tempdir().unwrap();
        let config = valid_config(iso_dir.path(), tftp_dir.path());

        assert!(config.validate().is_ok());
    }

    #[test]
    fn missing_iso_folder_fails() {
        let tftp_dir = tempfile::tempdir().unwrap();
        let config = valid_config(std::path::Path::new("/does/not/exist"), tftp_dir.path());

        assert!(config.validate().is_err());
    }

    #[test]
    fn any_missing_iso_folder_in_list_fails() {
        let iso_dir = tempfile::tempdir().unwrap();
        let tftp_dir = tempfile::tempdir().unwrap();
        let mut config = valid_config(iso_dir.path(), tftp_dir.path());
        config
            .iso_folder_paths
            .push(std::path::PathBuf::from("/does/not/exist"));

        assert!(config.validate().is_err());
    }

    #[test]
    fn missing_tftp_root_fails() {
        let iso_dir = tempfile::tempdir().unwrap();
        let config = valid_config(iso_dir.path(), std::path::Path::new("/does/not/exist"));

        assert!(config.validate().is_err());
    }

    #[test]
    fn missing_per_interface_tftp_root_override_fails() {
        use crate::config::schema::DhcpInterface;

        let iso_dir = tempfile::tempdir().unwrap();
        let tftp_dir = tempfile::tempdir().unwrap();
        let mut config = valid_config(iso_dir.path(), tftp_dir.path());
        config.dhcp_interfaces = vec![DhcpInterface {
            id: 1,
            name: "eth5".to_string(),
            gateway: "192.168.1.1".parse().unwrap(),
            default_iso: None,
            default_script: None,
            tftp_root: Some(std::path::PathBuf::from("/does/not/exist")),
            reservations: Vec::new(),
        }];

        let err = config.validate().unwrap_err().to_string();
        assert!(
            err.contains("eth5"),
            "error should name the offending interface: {err}"
        );
    }

    #[test]
    fn valid_per_interface_tftp_root_override_passes() {
        use crate::config::schema::DhcpInterface;

        let iso_dir = tempfile::tempdir().unwrap();
        let tftp_dir = tempfile::tempdir().unwrap();
        let override_dir = tempfile::tempdir().unwrap();
        let mut config = valid_config(iso_dir.path(), tftp_dir.path());
        config.dhcp_interfaces = vec![DhcpInterface {
            id: 1,
            name: "eth5".to_string(),
            gateway: "192.168.1.1".parse().unwrap(),
            default_iso: None,
            default_script: None,
            tftp_root: Some(override_dir.path().to_path_buf()),
            reservations: Vec::new(),
        }];

        assert!(config.validate().is_ok());
    }

    #[test]
    fn missing_runtime_root_fails() {
        let iso_dir = tempfile::tempdir().unwrap();
        let tftp_dir = tempfile::tempdir().unwrap();
        let mut config = valid_config(iso_dir.path(), tftp_dir.path());
        config.runtime_root = std::path::PathBuf::from("/does/not/exist");

        assert!(config.validate().is_err());
    }

    #[test]
    fn duplicate_interface_ids_fail() {
        let iso_dir = tempfile::tempdir().unwrap();
        let tftp_dir = tempfile::tempdir().unwrap();
        let mut config = valid_config(iso_dir.path(), tftp_dir.path());
        config.dhcp_interfaces = vec![
            DhcpInterface {
                id: 1,
                name: "eth0".to_string(),
                gateway: "192.168.1.1".parse().unwrap(),
                default_iso: None,
                default_script: None,
                tftp_root: None,
                reservations: Vec::new(),
            },
            DhcpInterface {
                id: 1,
                name: "eth1".to_string(),
                gateway: "192.168.2.1".parse().unwrap(),
                default_iso: None,
                default_script: None,
                tftp_root: None,
                reservations: Vec::new(),
            },
        ];

        assert!(config.validate().is_err());
    }

    #[test]
    fn missing_autoinstall_script_fails() {
        use crate::config::schema::AutoinstallScript;

        let iso_dir = tempfile::tempdir().unwrap();
        let tftp_dir = tempfile::tempdir().unwrap();
        let mut config = valid_config(iso_dir.path(), tftp_dir.path());
        config.autoinstall.insert(
            "foo.iso".to_string(),
            vec![AutoinstallScript {
                name: "seed".to_string(),
                script_path: std::path::PathBuf::from("/does/not/exist/seed"),
            }],
        );

        assert!(config.validate().is_err());
    }
}
