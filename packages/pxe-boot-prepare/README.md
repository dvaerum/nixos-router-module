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

# Show detected distro and GRUB menu-entry count per ISO
pxe-boot-prepare --config config.json status
```

## Configuration

See `examples/example_config.json` for a complete configuration example.

### Required Fields

- `iso_folder_paths`: List of directories to scan for ISO files
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
├── isos/
│   └── nixos.iso        (symlink -> Nix store or source dir; raw whole-ISO download)
└── unattented-install/
    ├── rhel.iso/
    │   └── minimal.kstart       (RHEL/Rocky/Alma: flat file, served verbatim)
    └── ubuntu.iso/
        └── minimal.ks/
            ├── user-data        (Ubuntu: NoCloud seed directory)
            └── meta-data

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

## Security Model

This service is designed for a **private, trusted LAN only** -- it is not
hardened against a hostile local network, and should not be exposed to one.

- **TFTP and HTTP are both plain, unauthenticated protocols.** Anyone who
  can reach the PXE-serving interface can download any ISO, script, or
  GRUB config this service serves. Autoinstall/kickstart scripts in
  particular may end up world-readable in the Nix store AND served
  unauthenticated over the network -- see the `SECURITY` note on
  `pxe-boot.autoinstall.*.script` in `nixosModule/options.nix` for why
  secrets must never be placed directly in one.
- **Secure Boot (see `nixosModule/options.nix`'s `shimPackage` option and
  `tests/pxe-boot/secure-boot.nix`) covers the boot CHAIN, not everything
  a booted client subsequently does.** Concretely: shim + GRUB + kernel
  are cryptographically verified against Microsoft/Canonical's trust
  anchors before any of them execute, so a network attacker cannot forge
  a fake signed bootloader or kernel. That guarantee ends the moment the
  verified kernel hands off to its own init/installer -- the ISO's
  payload content, and any autoinstall/kickstart script fetched over
  plain HTTP post-boot, are **not** covered by Secure Boot's signature
  chain at all. A client that has successfully verified its boot chain
  still implicitly trusts "whatever this PXE server serves next" for
  everything after that point.
- **TLS/certificate-based transport security was considered and declined
  for this LAN-only use case**, not merely deferred: bootstrapping a
  trusted certificate chain for a PXE service that itself runs *before*
  a client has any OS, network stack, or cert store of its own to
  validate against is circular -- there is no earlier point in the boot
  process to anchor that trust from. Secure Boot's hardware/firmware-
  rooted trust anchor is the mechanism that actually fits this
  bootstrapping problem; a from-scratch TLS trust chain would not add
  real security here, only complexity.

The practical implication for operators: treat every device that can
reach a PXE-enabled interface as implicitly trusted to receive (not just
request) any ISO/script this service is configured to serve. Firewalling
or VLAN-isolating that interface, not adding transport encryption, is the
correct control for a network you don't fully trust.

## TODO

### NFS boot for Ubuntu (lower install-time RAM)

Ubuntu boots via `url=<iso>`, loading the whole ISO into RAM. With cloud-init
26.04's ~5.5 GB footprint (a cloud-init bug, not our seed) the install peaks
around ~10 GB — so give Ubuntu VMs **≥12 GB** for now. The autoinstall itself is
correct; only the boot RAM is the issue.

Fix: serve the ISO tree over NFS and boot `netboot=nfs`, keeping the squashfs on
the server instead of in RAM (HTTP `fetch=` doesn't work — casper needs the whole
`/casper` as one medium):

- Export `/run/pxe-boot/iso-mountpoint` read-only via NFS.
- In `src/distro/ubuntu.rs`, replace `url=<iso>` with
  `boot=casper netboot=nfs nfsroot=<gw>:/run/pxe-boot/iso-mountpoint/<iso>` +
  `layerfs-path=<deepest casper/*.squashfs>`.
- Keep the working `autoinstall ds=nocloud;s=<dir>/` seed.

## Development

Build with Cargo:

```bash
cargo build --release
```

Run tests:

```bash
cargo test
```
