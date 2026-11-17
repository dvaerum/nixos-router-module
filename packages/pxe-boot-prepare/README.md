# PXE Boot Prepare

Automated PXE boot environment preparation from ISO files.

## Features

- **Automatic ISO Discovery**: Scans directory for ISO files
- **Smart Mounting**: Mounts ISOs with verification and deduplication
- **Multi-Distribution Support**: NixOS, Ubuntu (Server and Desktop), RHEL/Rocky/Alma Linux
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
   `casper/ubuntu-server-minimal.squashfs` (Server), or `casper/vmlinuz`
   together with a `.disk/info` naming Ubuntu (Desktop and flavours)
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

## NFS boot

With `my.router.pxe-boot.nfs.enable = true` the mounted ISOs are exported read-only
over NFSv3 and every ISO whose distro supports it boots from there instead of
downloading the whole ISO into RAM. Other distros keep using HTTP.

```text
  ISO file --pxe-boot-prepare--> /run/pxe-boot/iso-mountpoint/<iso>
                                      |  one export per ISO, fsid derived from its name
                                      v
  /etc/exports.d/pxe-boot.exports --exportfs -r--> NFS server --> client (netboot=nfs)
```

- **One export per ISO** with an explicit `fsid=`: nfsd otherwise derives the ID from the
  ISO's creation timestamp, and two ISOs built in the same second get served as each other.
- **Cleanup unexports first, then unmounts**, retrying a busy unmount for
  `nfs.unmountRetrySecs` (nfsd holds an ISO ~20 s after a client's last read).
- Pin one ISO to HTTP with `nfs.httpOnlyIsos`. Options: see [options](../../docs/options.md).
- The module does not manage a firewall; allow 111, 2049 and `nfs.mountdPort` from the PXE
  networks only. Exports are limited to those networks' subnets.

## TODO

### NFS boot: remaining work

Confirmed on real hardware: Ubuntu 26.04.1 Desktop boots all the way over NFS
(initrd mounts the export, casper's default squashfs layer is found).

Not done or not confirmed:

- Unattended Desktop install over NFS (the Server `autoinstall` seed is passed through).
- RHEL over NFS (`inst.stage2`): not implemented, RHEL keeps the HTTP path.
- A refresh that leaves unchanged ISOs alone: today a refresh restarts
  everything, which breaks a client that is mid-install over NFS.
- A VM test that boots a client over NFS (only the wiring is covered by
  `pxe-boot-nfs-wiring`).

## Development

Build with Cargo:

```bash
cargo build --release
```

Run tests:

```bash
cargo test
```
