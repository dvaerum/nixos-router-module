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

    install --target-directory "$out" \
      "bootx64.efi" \
      "pxelinux.0"
  '';

  meta = {
    license = lib.licenses.gpl3Plus;
  };
}
