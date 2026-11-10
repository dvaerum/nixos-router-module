{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [ ./. ];

  # Enable the PXE-bootable ISO configuration
  pxe-boot-iso.enable = true;

  # Include all tool categories by default
  pxe-boot-iso.includeNetworkTools = true;
  pxe-boot-iso.includeDiskTools = true;
  pxe-boot-iso.includeHardwareTools = true;

  # Enable network ISO download feature
  pxe-boot-iso.enableNetworkDownload = true;

  # Kernel: left unset on purpose. The default is the newest kernel the ZFS
  # package supports (see docs/zfs-kernel-selection.md); pinning
  # `linuxPackages_latest` here would break the ISO build whenever nixpkgs gets a
  # kernel ZFS does not support yet.

  # ISO metadata
  image.fileName = lib.mkForce "nixos-pxe-boot-${pkgs.stdenv.hostPlatform.system}.iso";
  isoImage.volumeID = lib.mkForce "NIXOS_PXE_BOOT";
}
