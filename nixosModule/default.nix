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
  ];

  options = {};

  config = import ./config.nix { inherit pkgs lib config; };
}
