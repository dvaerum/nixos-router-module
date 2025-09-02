{ pkgs ? import <nixpkgs> {}
, ...
}: let

  inherit (pkgs)
    lib
    fetchurl
    stdenvNoCC
    fetchFromGitHub
    ubootRaspberryPi4_64bit
  ;

  pkgsCross = import pkgs.path {
    localSystem = {
      system = "x86_64-linux";
    };
    crossSystem = {
      system = "x86_64-linux";
    };
  };

  # Build the GRUB Legacy BIOS binary for PXE Boot on any architecture
  legacy_bios_grub_pxe = pkgs.runCommand "grub-legacy-pxe-boot" {
    buildInputs = [ pkgs.qemu ];
  } ''
    mkdir -p $out
    ${pkgsCross.qemu}/bin/qemu-x86_64 -L ${pkgsCross.glibc} \
      ${pkgsCross.grub2}/bin/grub-mkimage \
        -O i386-pc-pxe \
        -o "$out/grub.pxe" \
        -p /grub \
        pxe tftp http configfile normal linux
  '';

  raspberrypi_4_config_txt = pkgs.writeTextDir "config.txt" ''
    arm_64bit=1
    uart_2ndstage=1
    enable_uart=1
    kernel=u-boot.bin
  '';


in stdenvNoCC.mkDerivation rec {
  pname = "grub-netboot-with-secure-boot";
  version = "24.04.3";

  srcs = [
    ( fetchurl {
      url = "https://releases.ubuntu.com/${lib.strings.substring 0 5 version}/ubuntu-${version}-netboot-amd64.tar.gz";
      hash = "sha256-eSXr1ipHvUCF7iqgZVyVSPgl9E8Ok8KsHjyyx5jvic0=";
    })
    ( fetchurl {
      url = "https://cdimage.ubuntu.com/releases/${version}/release/ubuntu-${version}-netboot-arm64.tar.gz";
      hash = "sha256-NoleWmizfaPPcf+C/SEG2SPv37IPPbH/oR5VKT4WKnQ=";
    })
  ];

  sourceRoot = ".";


  dontPatch = true;
  dontConfigure = true;

  # buildPhase = ''
  #   find .
  # '';

  installPhase = ''
    install --verbose --directory "$out"

    # Grub Legacy Boot
    install --verbose --mode 0444 --target-directory "$out" \
      "${legacy_bios_grub_pxe}/grub.pxe"

    # Grub UEFI Boot (x86_64)
    install --verbose --mode 0444 --target-directory "$out" \
      "./amd64/bootx64.efi" \
      "./amd64/grubx64.efi"

    # Grub UEFI Boot (aarch64)
    install --verbose --mode 0444 --target-directory "$out" \
      "./arm64/bootaa64.efi" \
      "./arm64/grubaa64.efi"

    # Raspberry PI 4
    install --verbose --mode 0444 --target-directory "$out" \
      "${pkgs.raspberrypifw}/share/raspberrypi/boot/start4.elf" \
      "${pkgs.raspberrypifw}/share/raspberrypi/boot/fixup4.dat" \
      "${pkgs.raspberrypifw}/share/raspberrypi/boot/bcm2711-rpi-4-b.dtb" \
      "${raspberrypi_4_config_txt}/config.txt" \
      "${ubootRaspberryPi4_64bit}/u-boot.bin"
    mkdir -p "$out/overlays"
    install --verbose --mode 0444 \
      "${pkgs.raspberrypifw}/share/raspberrypi/boot/overlays/overlay_map.dtb" \
      "$out/overlays/overlay_map.dtb"

  '';

  meta = {
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
  };
}
