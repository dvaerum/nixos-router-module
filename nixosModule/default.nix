{ config
, pkgs
, lib
, stdenv
, pimd
, options
, ...
}:

{
  imports = [];

  options = import ./options.nix { inherit pkgs lib options; };

  config = import ./config.nix { inherit pkgs lib config; };
}
