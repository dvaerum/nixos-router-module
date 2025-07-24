{ config
, pkgs
, lib
, stdenv
, pimd
, options
, ...
}:

{
  imports = [
    ./options.nix

    ./config.nix
    ./config-tftp.nix
  ];

  options = {};

  config = {};
}
