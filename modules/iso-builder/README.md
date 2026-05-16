# ISO Builder Module

This module provides an easy way to build custom PXE-bootable NixOS ISO images with pre-configured tools and settings.

## Features

- **Network Tools**: tcpdump, nmap, iperf3, ethtool, mtr, dig, and more
- **Disk Utilities**: parted, gparted, testdisk, smartmontools, nvme-cli
- **Hardware Testing**: lshw, hwinfo, dmidecode, stress-ng
- **Network Boot Support**: Download ISO over network during boot with `findiso=http://...` kernel parameter
- **ZFS Support**: Pre-configured for ZFS installations
- **SSH Access**: Easy remote access with authorized keys
- **Cross-platform**: Build for x86_64 and aarch64

## Quick Start

### Building ISOs

```bash
# Build basic ISO for your current system architecture
nix build .#iso

# Build for specific architectures
nix build .#iso-x86_64       # x86_64 Linux
nix build .#iso-aarch64      # aarch64 Linux (ARM64)

# Build the example ISO (with customizations)
nix build .#iso-example
nix build .#iso-x86_64-example
nix build .#iso-aarch64-example
```

The built ISO will be available at `./result/iso/*.iso`

### Using the ISO

1. **Local boot**: Write the ISO to a USB drive or burn to CD/DVD
   ```bash
   dd if=./result/iso/nixos-pxe-boot-*.iso of=/dev/sdX bs=4M status=progress
   ```

2. **PXE boot**: Place the ISO in your PXE server's ISO directory
   - The `pxe-boot-prepare` tool will automatically discover and configure it

3. **Network download**: Boot with kernel parameter `findiso=http://server/path/to.iso`
   - The ISO will be downloaded over the network during boot

### Login

- **User**: `nixos` (password-less, but SSH key auth recommended)
- **Root**: `root` (password-less, but SSH key auth recommended)
- **Shell**: Fish (with fallback to bash)

## Customization

### Basic Customization

Create a custom configuration file (e.g., `my-iso.nix`):

```nix
{ config, lib, pkgs, ... }:

{
  imports = [ ./modules/iso-builder ];

  pxe-boot-iso = {
    enable = true;

    # Choose which tool categories to include
    includeNetworkTools = true;
    includeDiskTools = true;
    includeHardwareTools = true;

    # Add your custom packages
    extraPackages = with pkgs; [
      vim
      htop
      tmux
    ];

    # Add SSH keys for remote access
    sshAuthorizedKeys = [
      "ssh-ed25519 AAAAC3Nz... user@host"
    ];

    # Choose kernel version
    kernelPackage = pkgs.linuxPackages_latest;
  };

  # Set system state version
  system.stateVersion = lib.trivial.release;
}
```

Then build it:

```bash
nix build .#packages.x86_64-linux.my-custom-iso \
  --override-input nixosSystem ./my-iso.nix
```

### Advanced Customization

You can add any NixOS configuration to your custom ISO:

```nix
{
  imports = [ ./modules/iso-builder ];

  pxe-boot-iso.enable = true;

  # Custom services
  services.tailscale.enable = true;

  # Custom environment variables
  environment.variables = {
    EDITOR = "nvim";
  };

  # Custom systemd services
  systemd.services.my-service = {
    description = "My Custom Service";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.bash}/bin/bash -c 'echo Hello'";
    };
  };
}
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable PXE-bootable ISO configuration |
| `extraPackages` | list | `[]` | Additional packages to include |
| `includeNetworkTools` | bool | `true` | Include network troubleshooting tools |
| `includeDiskTools` | bool | `true` | Include disk utilities |
| `includeHardwareTools` | bool | `true` | Include hardware testing tools |
| `sshAuthorizedKeys` | list | `[]` | SSH keys for nixos/root users |
| `kernelPackage` | package | `linuxPackages_latest` | Kernel package to use |
| `enableNetworkDownload` | bool | `true` | Enable ISO download via network |

## Integration with PXE Boot Server

This ISO builder module is designed to work seamlessly with the main router module's PXE boot functionality:

1. Build your custom ISO:
   ```bash
   nix build .#iso-x86_64
   ```

2. Copy the ISO to your PXE server's ISO directory:
   ```bash
   cp ./result/iso/*.iso /path/to/pxe-server/isos/
   ```

3. The `pxe-boot-prepare` tool will automatically:
   - Discover the ISO
   - Mount it
   - Generate appropriate GRUB menu entries
   - Configure TFTP for serving boot files

4. Clients can then PXE boot and select your custom ISO from the boot menu

## Included Packages

### Network Tools
- `tcpdump` - Packet analyzer
- `nmap` - Network scanner
- `iperf3` - Network performance testing
- `ethtool` - Ethernet device settings
- `netcat` - Network Swiss Army knife
- `wget`, `curl` - File downloaders
- `traceroute`, `mtr` - Network diagnostics
- `dig`, `nslookup` - DNS utilities

### Disk Utilities
- `parted`, `gparted` - Partition editors
- `testdisk` - Data recovery
- `smartmontools` - SMART monitoring
- `hdparm` - Hard disk parameters
- `nvme-cli` - NVMe management

### Hardware Tools
- `lshw`, `hwinfo` - Hardware information
- `pciutils`, `usbutils` - Device utilities
- `dmidecode` - DMI/SMBIOS information
- `stress-ng` - Stress testing

### Essential Tools
- `git` - Version control
- `neovim` - Text editor
- `fish` - Friendly shell
- `tmux` - Terminal multiplexer
- `htop` - Process viewer
- `rsync` - File synchronization
- `jq` - JSON processor
- `fzf` - Fuzzy finder
- `disko` - Declarative disk partitioning

## Tips

1. **Reduce ISO size**: Disable tool categories you don't need:
   ```nix
   pxe-boot-iso.includeHardwareTools = false;
   ```

2. **Custom ISO name**: Override the `isoImage` options:
   ```nix
   isoImage.isoName = lib.mkForce "my-custom-name.iso";
   ```

3. **Multiple ISOs**: Create multiple configuration files for different use cases
   (e.g., `network-troubleshooting.nix`, `disk-recovery.nix`, `hardware-testing.nix`)

4. **Remote access**: Always add your SSH keys for headless operations:
   ```nix
   pxe-boot-iso.sshAuthorizedKeys = [ "your-ssh-key" ];
   ```

## Troubleshooting

### ISO doesn't boot
- Check that the ISO was written correctly to the USB drive
- Verify BIOS/UEFI settings allow booting from USB/Network
- Try different boot modes (UEFI vs Legacy)

### Network download fails
- Ensure the ISO URL is accessible from the network
- Check that `findiso=` kernel parameter is correctly formatted
- Verify network connectivity during initrd phase

### Missing packages
- Add them to `extraPackages` in your configuration
- Rebuild the ISO with the updated configuration

## Architecture Notes

### For aarch64 builds
Building for aarch64 on x86_64 requires:
- QEMU user emulation: `boot.binfmt.emulatedSystems = [ "aarch64-linux" ];`
- Or use a native aarch64 builder
- Cross-compilation is not yet fully supported for ISO images

Currently, aarch64 ISO builds may require additional testing and may not work out of the box for all hardware configurations.
