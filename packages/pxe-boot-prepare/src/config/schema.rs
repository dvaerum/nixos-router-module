use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::net::IpAddr;
use std::path::PathBuf;

/// Main configuration structure (maps from NixOS options)
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct PxeBootConfig {
    /// Path to folder containing ISO files
    pub iso_folder_path: PathBuf,

    /// TFTP root folder (default: /srv/pxeboot)
    pub tftp_root: PathBuf,

    /// Runtime folder (default: /run/pxe-boot)
    pub runtime_root: PathBuf,

    /// DHCP interfaces with PXE boot enabled
    pub dhcp_interfaces: Vec<DhcpInterface>,

    /// Autoinstall scripts mapped to ISOs
    #[serde(default)]
    pub autoinstall: HashMap<String, Vec<AutoinstallScript>>,

    /// HTTP server configuration
    pub http: HttpConfig,
}

/// DHCP interface configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DhcpInterface {
    pub id: u32,
    pub name: String,
    pub gateway: IpAddr,
    pub default_iso: Option<String>,
    pub default_script: Option<String>,
}

/// Autoinstall script definition
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct AutoinstallScript {
    pub name: String,
    pub script_path: PathBuf,
}

/// HTTP server configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct HttpConfig {
    pub mount_port: u16, // default: 1337
    pub iso_port: u16,   // default: 1338
}

/// Discovered ISO information
#[derive(Debug, Clone)]
pub struct IsoInfo {
    pub file_name: String,
    pub file_path: PathBuf,
    pub mount_path: PathBuf,
    pub distro_type: DistroType,
    pub kernel_path: PathBuf,
    pub initrd_path: PathBuf,
}

/// Distribution type enumeration
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DistroType {
    NixOS,
    Ubuntu,
    RedHat,
    Unknown(String),
}

/// Boot information extracted from ISO
#[derive(Debug, Clone)]
pub struct BootInfo {
    pub kernel_path: PathBuf,
    pub initrd_path: PathBuf,
    pub distro_type: DistroType,
    pub version: Option<String>,
    pub architecture: Option<String>,
}

/// GRUB menu entry
#[derive(Debug, Clone)]
pub struct MenuEntry {
    pub title: String,
    pub kernel_url: String,
    pub kernel_params: Vec<String>,
    pub initrd_url: String,
    pub position: usize,
}
