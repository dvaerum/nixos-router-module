{
  config,
  lib,
  pkgs,
  ...
}:

# Example configuration showing customization options
# This demonstrates how to create a custom ISO with additional packages and configuration

{
  imports = [ ./. ];

  # Enable the PXE-bootable ISO configuration
  pxe-boot-iso = {
    enable = true;

    # Customize which tool categories to include
    includeNetworkTools = true;
    includeDiskTools = true;
    includeHardwareTools = true;

    # Add custom packages
    extraPackages = with pkgs; [
      # Your custom tools here
      vim
      btop
      tree
      ripgrep
      fd
    ];

    # Add SSH keys for remote access
    sshAuthorizedKeys = [
      # "ssh-ed25519 AAAAC3Nz... user@host"
    ];

    # Kernel: unset, so the newest one the ZFS package supports is used.
    # To pin one instead: kernelPackage = pkgs.linuxPackages_6_12;

    # Enable network download feature
    enableNetworkDownload = true;
  };

  # Additional custom configuration can go here
  # For example, custom services, environment variables, etc.

  # Set timezone
  time.timeZone = "UTC";

  # Customize ISO name
  image.fileName = lib.mkForce "custom-pxe-boot-${pkgs.stdenv.hostPlatform.system}.iso";
  isoImage.volumeID = lib.mkForce "CUSTOM_PXE_BOOT";

}
