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
  vxlan = import ./vxlan.nix { inherit pkgs nixosModule; };
  dns-server = dns-server.vm;
  dns-server-disabled = dns-server.disabledCheck;
  pxe-boot = pxe-boot.vm;
  pxe-boot-tftp-warnings = pxe-boot.tftpWarningsCheck;
  pxe-boot-secure-boot = (import ./pxe-boot/secure-boot.nix { inherit pkgs nixosModule; }).vm;
}
