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
- **A changed ISO folder is refreshed incrementally** (`pxe-boot-prepare refresh`, run by
  `pxe-boot-prepare-refresh.service`), not by restarting the service: ISOs that are still
  there and unchanged (same inode, size and mtime) stay mounted and exported, so a client
  installing from one is not cut off when another is added or removed. A removed or
  changed ISO is first dropped from the exports (`exportfs -r` re-reads them and keeps the
  unchanged ones), then unmounted with the same busy retry; one that is still busy
  afterwards is left mounted, logged, and retried by the next refresh.
- Pin one ISO to HTTP with `nfs.httpOnlyIsos`. Options: see [options](../../docs/options.md).
- The module does not manage a firewall; allow 111, 2049 and `nfs.mountdPort` from the PXE
  networks only. Exports are limited to those networks' subnets.

## TODO

### NFS boot: status and remaining work

| Distro | Real hardware | Automated test |
|---|---|---|
| Ubuntu 26.04.1 Desktop | boots over NFS into the installer | unit tests, config check |
| NixOS (this project's ISO builder) | boots over NFS to the live system (kernel and initrd over HTTP, the ISO tree over NFS, no whole-ISO download) | VM test: PXE client boots over NFS and sends its beacon |
| RHEL 10.2 | full interactive and unattended (kickstart) installs completed over NFS (installer image and packages, about 2 GB read over NFS, none over HTTP; the kickstart itself is an HTTP fetch) | unit tests, VM test of the export, the menu entry and the installer's exact repo mount (mock ISO) |

RHEL 9.6 uses the same boot parameters and was seen reaching the same mounts; only 10.2
was installed end to end. It boots with `inst.repo=nfs:<router>:<mounted ISO>/`: the installer mounts that
export as its repo and loop-mounts `images/install.img` from it (checked against
the real RHEL 9.6 and 10.2 initrds' dracut scripts; defaults to NFS version 3).
The trailing slash matters: anaconda treats an `nfs:` repo ending in `.iso` as an ISO
*file* and mounts its parent directory, and an ISO's mount point is a directory named
after the file (found on real hardware: "mount.nfs: access denied by server").

Not done or not confirmed:

- Unattended Ubuntu installs (autoinstall) over NFS: the seed is passed through
  unchanged and stays an HTTP fetch, as the RHEL kickstart does, but it has not been
  run.
- The incremental refresh is covered by a VM test (`pxe-boot-nfs-refresh`: a reader keeps
  a file of one ISO open over NFS while another ISO is added, replaced and removed), not
  yet by a real install on hardware. Menus are rewritten only after the removed ISO's
  unmount finishes, so a removed ISO can stay listed for as long as nfsd holds it (about
  20 s measured).

## Development

Build with Cargo:

```bash
cargo build --release
```

Run tests:

```bash
cargo test
```
