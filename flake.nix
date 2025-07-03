{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    utils.url = "github:numtide/flake-utils";

    pimd = {
      url = "github:dvaerum/nixos-pimd-module";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        utils.follows = "utils";
      };
    };
  };


  outputs = { self, pimd, ... }:
    {
      # To-do: Figure out how to make nested overlays
      overlays.default = pimd.overlays.default;

      nixosModules.default = { ... }: {
        imports = [
          pimd.nixosModules.default
          ./nixosModule
        ];
        options = {};
        config = {};
      };
    };
}
