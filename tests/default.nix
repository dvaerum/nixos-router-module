{
  pkgs ? import <nixpkgs> { },
  nixosModule ? ../.,
}:
let
  dns-server = import ./dns-server.nix { inherit pkgs nixosModule; };
  pxe-boot = import ./pxe-boot { inherit pkgs nixosModule; };
in
{
  basic-routing = import ./basic-routing.nix { inherit pkgs nixosModule; };
  dhcp-server = import ./dhcp-server.nix { inherit pkgs nixosModule; };
  dhcp-client-use-routes = import ./dhcp-client-use-routes.nix { inherit pkgs nixosModule; };
  vxlan = import ./vxlan.nix { inherit pkgs nixosModule; };
  dns-server = dns-server.vm;
  dns-server-disabled = dns-server.disabledCheck;
  pxe-boot = pxe-boot.vm;
  pxe-boot-tftp-warnings = pxe-boot.tftpWarningsCheck;
  pxe-boot-kea-client-classes = pxe-boot.keaPxeClientClassesCheck;
  pxe-boot-nix-isos-wiring = pxe-boot.nixIsosWiringCheck;
  pxe-boot-iso-download-rate-limit = pxe-boot.isoDownloadRateLimitCheck;
  pxe-boot-full-disable = pxe-boot.fullDisableCheck;
  pxe-boot-secure-boot = (import ./pxe-boot/secure-boot.nix { inherit pkgs nixosModule; }).vm;
  iso-builder-network-download-options = import ./iso-builder-network-download-options.nix {
    inherit pkgs;
  };
}
