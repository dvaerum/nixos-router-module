# PXE Boot Prepare

Automated PXE boot environment preparation from ISO files.

## Features

- **Automatic ISO Discovery**: Scans directory for ISO files
- **Smart Mounting**: Mounts ISOs with verification and deduplication
- **Multi-Distribution Support**: NixOS, Ubuntu Server, RHEL/Rocky/Alma Linux
- **Plugin Architecture**: Extensible distribution detector system
- **GRUB Menu Generation**: Dynamic GRUB configuration from discovered ISOs
- **Autoinstall Support**: Kickstart and other unattended installation scripts
- **Multi-Interface**: Different boot menus per DHCP network

## Usage

```bash
# Prepare PXE boot environment
pxe-boot-prepare --config config.json prepare

# List discovered ISOs
pxe-boot-prepare --config config.json list

# Validate configuration
pxe-boot-prepare --config config.json validate

# Cleanup mounted ISOs
pxe-boot-prepare --config config.json cleanup
```

## Configuration

See `examples/example_config.json` for a complete configuration example.

### Required Fields

- `iso_folder_path`: Path to directory containing ISO files
- `tftp_root`: TFTP server root directory (usually `/srv/pxeboot`)
- `runtime_root`: Runtime directory for mounts (usually `/run/pxe-boot`)
- `dhcp_interfaces`: List of DHCP interfaces with PXE boot enabled
- `http`: HTTP server ports configuration

### Optional Fields

- `autoinstall`: Map of ISO names to autoinstall scripts

## Architecture

### Distribution Detection

The tool uses a priority-based detector system. Each detector implements the
`DistroDetector` trait:

1. **NixOS Detector** (priority 60): Looks for `nix-store.squashfs`
2. **Ubuntu Detector** (priority 55): Looks for
   `casper/ubuntu-server-minimal.squashfs`
3. **RHEL Detector** (priority 50): Looks for `RPM-GPG-KEY-redhat-release`

### GRUB Menu Generation

For each DHCP interface, generates a GRUB configuration with:

- Boot entries for each detected ISO
- Additional entries for autoinstall scripts
- Default selection based on configuration
- "Reload Grub" entry for live updates

### Directory Structure

```
/run/pxe-boot/
├── iso-mountpoint/
│   ├── nixos.iso/       (mounted ISO)
│   └── rhel.iso/        (mounted ISO)
└── unattented-install/
    └── rhel.iso/
        └── minimal.kstart

/srv/pxeboot/
└── {dhcp-id}/
    ├── grub.pxe
    ├── grubx64.efi
    └── grub/
        └── grub.cfg     (generated)
```

## NixOS Integration

This tool is designed to integrate with the `nixos-router-module`. The NixOS
module automatically generates the JSON configuration from declarative options.

See `nixosModule/config-tftp.nix` for the integration.

## Development

Build with Cargo:

```bash
cargo build --release
```

Run tests:

```bash
cargo test
```
