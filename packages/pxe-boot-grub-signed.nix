{ pkgs ? import <nixpkgs> {}
, ...
}:

with pkgs;
stdenvNoCC.mkDerivation rec {
  pname = "grub-netboot-with-secure-boot";
  version = "24.04.3";

  src = fetchurl {
    url = "https://releases.ubuntu.com/${lib.strings.substring 0 5 version}/ubuntu-${version}-netboot-amd64.tar.gz";
    hash = "sha256-eSXr1ipHvUCF7iqgZVyVSPgl9E8Ok8KsHjyyx5jvic0=";
  };

  dontPatch = true;
  dontConfigure = true;

  nativeBuildInputs = [ grub2 ];

  buildPhase = ''
    grub-mkimage \
      -O i386-pc-pxe \
      -o "grub.pxe" \
      -p /grub \
      pxe tftp http configfile normal linux

    ls -la
  '';

  installPhase = ''
    install --directory "$out"

    install --mode 0444 --target-directory "$out" \
      "grub.pxe" \
      "bootx64.efi" \
      "grubx64.efi"
  '';

  meta = {
    license = lib.licenses.gpl3Plus;
  };
}
