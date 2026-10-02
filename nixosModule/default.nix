{
  config,
  pkgs,
  lib,
  stdenv,
  pimd,
  options,
  ...
}:
{
  imports = [
    ./options.nix

    ./config.nix
    ./config-tftp.nix
    ./config-dns.nix
  ];

  options = { };

  config = { };
}
