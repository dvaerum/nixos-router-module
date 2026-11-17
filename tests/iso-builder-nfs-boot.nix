{
  pkgs ? import <nixpkgs> { },
}:
###########################################################################
# Pure-eval check (no VM, no ISO build): the ISO builder's `enableNfsBoot`
# wires NFS support into the initrd, the `nfsiso-configure` unit, and the
# marker file pxe-boot-prepare uses to recognise such an ISO. The real
# boot over NFS is tested in the `pxe-boot-nixos-nfs` VM test.
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

  default = evaluated { };
  nfsOff = evaluated { pxe-boot-iso.enableNfsBoot = false; };
  nfsOnly = evaluated {
    pxe-boot-iso.enableNetworkDownload = false;
    pxe-boot-iso.enableNfsBoot = true;
  };

  featuresOf =
    c:
    let
      entry = builtins.head (
        builtins.filter (e: e.target == "/pxe-boot-iso-features") c.isoImage.contents
      );
    in
    lib.splitString "\n" (lib.removeSuffix "\n" (builtins.readFile entry.source));

  unitsOf = c: c.boot.initrd.systemd.services;

  checks = [
    {
      name = "on by default: nfsiso-configure unit exists";
      ok = (unitsOf default) ? "nfsiso-configure";
    }
    {
      name = "on by default: the nfs kernel module is in the initrd";
      ok = builtins.elem "nfs" default.boot.initrd.kernelModules;
    }
    {
      name = "on by default: the NFSv3 kernel module is in the initrd (mount(2) fails without it)";
      ok = builtins.elem "nfsv3" default.boot.initrd.kernelModules;
    }
    {
      name = "on by default: libtirpc's netconfig is in the initrd (mount.nfs cannot find tcp without it)";
      ok = default.boot.initrd.systemd.contents ? "/etc/netconfig";
    }
    {
      name = "on by default: protocols and services databases are in the initrd";
      ok =
        default.boot.initrd.systemd.contents ? "/etc/protocols"
        && default.boot.initrd.systemd.contents ? "/etc/services";
    }
    {
      name = "the mount forces TCP for both NFS and the mount protocol (the initrd kernel refuses UDP)";
      ok =
        lib.hasInfix "proto=tcp" (unitsOf default).nfsiso-configure.script
        && lib.hasInfix "mountproto=tcp" (unitsOf default).nfsiso-configure.script;
    }
    {
      name = "on by default: mount.nfs is in the initrd";
      ok = default.boot.initrd.systemd.extraBin ? "mount.nfs";
    }
    {
      name = "on by default: the marker file advertises nfsiso";
      ok = builtins.elem "nfsiso" (featuresOf default);
    }
    {
      name = "the unit reads nfsiso= from the kernel command line";
      ok = lib.hasInfix "nfsiso=" (unitsOf default).nfsiso-configure.script;
    }
    {
      name = "the unit runs before the /iso mount";
      ok = builtins.elem "sysroot-iso.mount" (unitsOf default).nfsiso-configure.before;
    }
    {
      name = "off: no nfsiso-configure unit";
      ok = !((unitsOf nfsOff) ? "nfsiso-configure");
    }
    {
      name = "off: no mount.nfs in the initrd";
      ok = !(nfsOff.boot.initrd.systemd.extraBin ? "mount.nfs");
    }
    {
      name = "off: the marker no longer advertises nfsiso";
      ok = !(builtins.elem "nfsiso" (featuresOf nfsOff));
    }
    {
      name = "off: findiso is still advertised (download support untouched)";
      ok = builtins.elem "findiso" (featuresOf nfsOff);
    }
    {
      name = "NFS without network download: the initrd still gets a DHCP network";
      ok = nfsOnly.boot.initrd.systemd.network.networks ? "40-findiso-dhcp";
    }
    {
      name = "NFS without network download: findiso is not advertised";
      ok = !(builtins.elem "findiso" (featuresOf nfsOnly));
    }
  ];

  failures = builtins.filter (c: !c.ok) checks;
in
pkgs.runCommand "iso-builder-nfs-boot-check" { } (
  if failures == [ ] then
    "touch $out"
  else
    throw "iso-builder NFS boot checks failed: ${builtins.toJSON (map (f: f.name) failures)}"
)
