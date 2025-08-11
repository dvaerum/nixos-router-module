{ pkgs ? import <nixpkgs> {}
, ...
}:

with pkgs;
stdenvNoCC.mkDerivation rec {
  pname = "grub-netboot-with-secure-boot";
  version = "24.04.2";

  src = fetchurl {
    url = "https://releases.ubuntu.com/${lib.strings.substring 0 5 version}/ubuntu-${version}-netboot-amd64.tar.gz";
    hash = "sha256-0aZfi6c3V6PccEviPDgwUP+KalChfOtRh1lb8kVQr0E=";
  };

  dontPatch = true;
  dontConfigure = true;

  buildPhase = ''
    ls -la
  '';

  installPhase = ''
    install --directory "$out"

    install --mode 0444 --target-directory "$out" \
      "bootx64.efi" \
      "pxelinux.0" \
      "grubx64.efi"


    install --directory "$out/linux"
    install --mode 0444 --target-directory "$out/linux" \
      "linux" \
      "initrd"
  '';

  meta = {
    license = lib.licenses.gpl3Plus;
  };
}
