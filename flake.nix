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

    # Pure-Nix IPv4/IPv6 CIDR library (replaces the ipcalc/python IFD helpers)
    nix-net-lib = {
      url = "github:0xCCF4/nix-net-lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      utils,
      pimd,
      nix-net-lib,
    }:
    let
      # Helper function to build ISO images
      mkIso = system: config: (import nixpkgs { inherit system; }).nixos config;
    in
    {
      # To-do: Figure out how to make nested overlays
      overlays.default = pimd.overlays.default;

      # Reusable helpers for other flakes: `inputs.<this>.lib.zfsKernel.select { pkgs; zfs; }`.
      lib.zfsKernel = import ./lib/zfs-kernel.nix;

      nixosModules = {
        default = { ... }: {
          imports = [
            pimd.nixosModules.default
            ./nixosModule
          ];
          options = { };
          # Expose the pure-Nix IP library to the module's helper files.
          config._module.args.netLib = nix-net-lib.lib;
        };

        # ISO builder module for creating PXE-bootable ISOs
        iso-builder = ./modules/iso-builder;
      };
    }
    // utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Import all tests
        tests = import ./tests {
          inherit pkgs;
          nixosModule = self;
        };

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
          dhcp-client-use-routes = tests.dhcp-client-use-routes;
          pxe-boot = tests.pxe-boot;
          pxe-boot-tftp-warnings = tests.pxe-boot-tftp-warnings;
          pxe-boot-kea-client-classes = tests.pxe-boot-kea-client-classes;
          pxe-boot-nix-isos-wiring = tests.pxe-boot-nix-isos-wiring;
          pxe-boot-iso-download-rate-limit = tests.pxe-boot-iso-download-rate-limit;
          pxe-boot-full-disable = tests.pxe-boot-full-disable;
          pxe-boot-secure-boot = tests.pxe-boot-secure-boot;
          iso-builder-network-download-options = tests.iso-builder-network-download-options;
          iso-builder-kernel-selection = tests.iso-builder-kernel-selection;
          vxlan = tests.vxlan;
          dns-server = tests.dns-server;
          dns-server-disabled = tests.dns-server-disabled;

          # Pure `lib.runTests` for the ZFS kernel selector, against a fake `pkgs`.
          zfs-kernel-lib =
            let
              failures = import ./lib/zfs-kernel_tests.nix { inherit pkgs; };
            in
            pkgs.runCommand "zfs-kernel-lib-tests" { } (
              if failures == [ ] then
                "touch $out"
              else
                throw "zfs-kernel lib tests failed:\n${builtins.toJSON failures}"
            );

          # The selector against the REAL nixpkgs: for the stable and the unstable ZFS
          # package it must pick a kernel whose ZFS module is not `meta.broken` and
          # that is not older than nixpkgs' default kernel. Catches nixpkgs API drift.
          zfs-kernel-real =
            if isLinux then
              let
                selector = import ./lib/zfs-kernel.nix;
                ok =
                  zfs:
                  let
                    kp = selector.select { inherit pkgs zfs; };
                  in
                  !(kp.${zfs.kernelModuleAttribute}.meta.broken or true)
                  && builtins.compareVersions kp.kernel.version pkgs.linuxPackages.kernel.version >= 0;
              in
              pkgs.runCommand "zfs-kernel-real" { } (
                if
                  builtins.all ok [
                    pkgs.zfs
                    pkgs.zfs_unstable
                  ]
                then
                  "touch $out"
                else
                  throw "zfs-kernel: selection against real nixpkgs gave an unsupported or too-old kernel"
              )
            else
              pkgs.runCommand "zfs-kernel-real-skipped" { } "touch $out";

          # Pure `lib.runTests` for the IPv4 helpers (returns [] when all pass).
          ipv4-lib =
            let
              failures = import ./nixosModule/functions/ipv4_tests.nix {
                inherit pkgs;
                netLib = nix-net-lib.lib;
              };
            in
            pkgs.runCommand "ipv4-lib-tests" { } (
              if failures == [ ] then
                "touch $out"
              else
                throw "ipv4 lib tests failed:\n${builtins.toJSON failures}"
            );
        };

        # Expose packages for building. Deliberately NOT mirroring `checks.*`
        # here (that was the pre-existing checks/packages drift: 13 `-test`
        # aliases with no content of their own) -- `nix build .#checks.<sys>.<name>`
        # already builds any check directly, so `packages` instead exposes the
        # project's actual standalone artifacts.
        packages = pkgs.lib.optionalAttrs isLinux (
          let
            # Explicitly named ISOs for cross-platform clarity
            archSuffix =
              if system == "x86_64-linux" then
                "x86_64"
              else if system == "aarch64-linux" then
                "aarch64"
              else
                system;
          in
          {
            # ISO images (only for Linux systems)
            iso = buildIso ./modules/iso-builder/basic.nix;
            iso-example = buildIso ./modules/iso-builder/example.nix;

            # Linux-only: calls `mount`/`umount` directly, same gate as the ISOs above.
            pxe-boot-prepare = pkgs.callPackage ./packages/pxe-boot-prepare/package.nix { };

            pxe-boot-grub-signed = import ./packages/pxe-boot-grub-signed/package.nix { inherit pkgs; };
          }
          // {
            # Architecture-specific names
            "iso-${archSuffix}" = buildIso ./modules/iso-builder/basic.nix;
            "iso-${archSuffix}-example" = buildIso ./modules/iso-builder/example.nix;
          }
        );
      }
    );
}
