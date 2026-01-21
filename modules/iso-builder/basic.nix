{ config, lib, pkgs, ... }:

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

  # Use latest stable kernel
  pxe-boot-iso.kernelPackage = pkgs.linuxPackages_latest;

  # ISO metadata
  isoImage = {
    isoName = lib.mkForce "nixos-pxe-boot-${pkgs.stdenv.hostPlatform.system}.iso";
    volumeID = lib.mkForce "NIXOS_PXE_BOOT";
  };
}
