{
  pkgs ? import <nixpkgs> { },
}:
###########################################################################
# Pure-eval check (no VM, no build): the ISO builder's default kernel is
# chosen by lib/zfs-kernel.nix from `boot.zfs.package`, and
# `pxe-boot-iso.kernel.{include,exclude}` and an explicit `kernelPackage`
# behave as documented. Asserts relationships, not fixed kernel numbers,
# so it keeps passing when nixpkgs bumps its kernels.
###########################################################################
let
  inherit (pkgs) lib;

  evaluated =
    extra:
    (pkgs.nixos (
      lib.recursiveUpdate {
        imports = [ ../modules/iso-builder ];
        pxe-boot-iso.enable = true;
      } extra
    )).config;

  kernelVersion = c: c.boot.kernelPackages.kernel.version;

  default = evaluated { };
  unstable = evaluated { boot.zfs.package = pkgs.zfs_unstable; };
  lts6 = evaluated { pxe-boot-iso.kernel.include = [ "linux_6_.*" ]; };
  nothingLeft = evaluated { pxe-boot-iso.kernel.exclude = [ ".*" ]; };
  pinnedWithEverythingExcluded = evaluated {
    pxe-boot-iso.kernelPackage = pkgs.linuxPackages;
    pxe-boot-iso.kernel.exclude = [ ".*" ];
  };

  # The shipped ISO definitions (what `nix build .#iso` / `.#iso-example` use) must
  # not pin a kernel, or they bypass the selection and break on a nixpkgs bump.
  # An unpinned option has exactly the module's own default definition, whose
  # location is the module directory; a pin adds a definition from another file.
  shippedPinsKernel =
    file:
    lib.any (d: toString d.file != toString ../modules/iso-builder)
      (pkgs.nixos file).options.pxe-boot-iso.kernelPackage.definitionsWithLocations;

  checks = [
    {
      name = "shipped basic.nix does not pin a kernel";
      ok = !(shippedPinsKernel ../modules/iso-builder/basic.nix);
    }
    {
      name = "shipped example.nix does not pin a kernel";
      ok = !(shippedPinsKernel ../modules/iso-builder/example.nix);
    }
    {
      name = "default: the ZFS kernel module is buildable (not meta.broken)";
      ok = !(default.boot.zfs.modulePackage.meta.broken or false);
    }
    {
      name = "default: not older than nixpkgs' default kernel";
      ok = builtins.compareVersions (kernelVersion default) pkgs.linuxPackages.kernel.version >= 0;
    }
    {
      name = "zfs_unstable: the ZFS kernel module is buildable (not meta.broken)";
      ok = !(unstable.boot.zfs.modulePackage.meta.broken or false);
    }
    {
      name = "kernel.include restricts the choice to the matching family";
      ok = lib.versions.major (kernelVersion lts6) == "6";
    }
    {
      name = "kernel.exclude removing everything makes the default throw";
      ok = !(builtins.tryEval (kernelVersion nothingLeft)).success;
    }
    {
      name = "an explicit kernelPackage wins over include/exclude";
      ok = kernelVersion pinnedWithEverythingExcluded == pkgs.linuxPackages.kernel.version;
    }
  ];

  failures = builtins.filter (c: !c.ok) checks;
in
pkgs.runCommand "iso-builder-kernel-selection-check" { } (
  if failures == [ ] then
    "touch $out"
  else
    throw "iso-builder kernel selection checks failed: ${builtins.toJSON (map (f: f.name) failures)}"
)
