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
    } // utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Import all tests
        tests = import ./tests { inherit pkgs; nixosModule = self; };
      in
      {
        # Expose tests as checks (run with: nix flake check)
        checks = {
          basic-routing = tests.basic-routing;
          dhcp-server = tests.dhcp-server;
          pxe-boot = tests.pxe-boot;
        };

        # Also expose tests as packages for manual building
        # (run with: nix build .#basic-routing-test)
        packages = {
          basic-routing-test = tests.basic-routing;
          dhcp-server-test = tests.dhcp-server;
          pxe-boot-test = tests.pxe-boot;
        };
      }
    );
}
