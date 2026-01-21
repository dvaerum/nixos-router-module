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


  outputs = { self, nixpkgs, utils, pimd }:
    let
      # Helper function to build ISO images
      mkIso = system: config: (import nixpkgs { inherit system; }).nixos config;
    in
    {
      # To-do: Figure out how to make nested overlays
      overlays.default = pimd.overlays.default;

      nixosModules = {
        default = { ... }: {
          imports = [
            pimd.nixosModules.default
            ./nixosModule
          ];
          options = {};
          config = {};
        };

        # ISO builder module for creating PXE-bootable ISOs
        iso-builder = ./modules/iso-builder;
      };
    } // utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Import all tests
        tests = import ./tests { inherit pkgs; nixosModule = self; };

        # Build ISOs for this system
        buildIso = config: (mkIso system config).config.system.build.isoImage;

        # Only build ISOs for Linux systems (not Darwin)
        isLinux = pkgs.stdenv.isLinux;
      in
      {
        # Expose tests as checks (run with: nix flake check)
        checks = {
          basic-routing = tests.basic-routing;
          dhcp-server = tests.dhcp-server;
          pxe-boot = tests.pxe-boot;
        };

        # Expose packages for building
        packages = {
          # Test packages
          basic-routing-test = tests.basic-routing;
          dhcp-server-test = tests.dhcp-server;
          pxe-boot-test = tests.pxe-boot;
        } // pkgs.lib.optionalAttrs isLinux (
          let
            # Explicitly named ISOs for cross-platform clarity
            archSuffix = if system == "x86_64-linux" then "x86_64"
                         else if system == "aarch64-linux" then "aarch64"
                         else system;
          in {
            # ISO images (only for Linux systems)
            iso = buildIso ./modules/iso-builder/basic.nix;
            iso-example = buildIso ./modules/iso-builder/example.nix;
          } // {
            # Architecture-specific names
            "iso-${archSuffix}" = buildIso ./modules/iso-builder/basic.nix;
            "iso-${archSuffix}-example" = buildIso ./modules/iso-builder/example.nix;
          }
        );
      }
    );
}
