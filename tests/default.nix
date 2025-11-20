{ pkgs ? import <nixpkgs> {}
, nixosModule ? ../.
}:

{
  basic-routing = import ./basic-routing.nix { inherit pkgs nixosModule; };
  dhcp-server = import ./dhcp-server.nix { inherit pkgs nixosModule; };
  pxe-boot = import ./pxe-boot.nix { inherit pkgs nixosModule; };
}
