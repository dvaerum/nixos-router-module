{
  pkgs ? import <nixpkgs> { },
  nixosModule ? ../../.,
}:
###########################################################################
# NixOS ISO over NFS: PXE boot integration test
###########################################################################
#
#   +-----------------------------------------------------------------+
#   |  router: DHCP + TFTP + HTTP + NFS server (pxe-boot.nfs.enable)  |
#   |    eth1: 192.168.90.1/24 --(vlan 1)-- pxeClient (UEFI, diskless) |
#   +-----------------------------------------------------------------+
#
# pxeClient PXE-boots the beacon ISO (see ./nixos-test-iso.nix). With NFS
# enabled the router exports the ISO's mounted tree and hands the client
# `nfsiso=<router>:<mount>` instead of `findiso=<url>`, so the initrd mounts
# the ISO from NFS rather than downloading it into RAM. The client's beacon
# request (sent only after a complete boot) is the proof; the absence of any
# `/isos/` request proves the whole-ISO download did not happen.
#
# This is what protects the nfsiso-configure unit in modules/iso-builder, the
# NixosDetector's nfsiso= parameters, and the router's per-ISO NFS exports
# from silently breaking each other.
###########################################################################
let
  routerIp = "192.168.90.1";
  httpPort = 1337;
  isoName = "nixos-pxe-nfs-test.iso";
  clientMac = "52:54:00:cc:01:03";

  testIso = import ./nixos-test-iso.nix {
    inherit
      pkgs
      routerIp
      httpPort
      isoName
      ;
    volumeID = "NIXOS_PXE_NFS";
  };

  # Mock RHEL ISOs, only to check what the router exports and writes into the
  # menu (a real RHEL boot is tested by hand): one with the installer image,
  # which can boot over NFS, and one without it, which must stay on HTTP.
  rhelNfsIsoName = "rhel-9.6-x86_64-dvd.iso";
  rhelHttpIsoName = "rhel-9.6-x86_64-boot-without-stage2.iso";

  mockRhel =
    name: withInstallImg:
    pkgs.runCommand "mock-${name}" { nativeBuildInputs = [ pkgs.xorriso ]; } ''
      mkdir -p $out rhel-root/images/pxeboot
      echo "Red Hat GPG Key" > rhel-root/RPM-GPG-KEY-redhat-release
      echo "Mock RHEL kernel" > rhel-root/images/pxeboot/vmlinuz
      echo "Mock RHEL initrd" > rhel-root/images/pxeboot/initrd.img
      ${pkgs.lib.optionalString withInstallImg ''echo "Mock stage2" > rhel-root/images/install.img''}
      xorriso -as mkisofs -o $out/${name} -V "RHEL-TEST" -r -J rhel-root/
    '';

  isoDir = pkgs.runCommand "nixos-nfs-test-iso-directory" { } ''
    mkdir -p $out
    cp ${testIso}/iso/*.iso $out/${isoName}
    cp ${mockRhel rhelNfsIsoName true}/${rhelNfsIsoName} $out/
    cp ${mockRhel rhelHttpIsoName false}/${rhelHttpIsoName} $out/
  '';
in
{
  vm = pkgs.testers.nixosTest {
    name = "router-pxe-boot-nixos-nfs";
    skipLint = false;

    nodes = {
      router =
        { pkgs, ... }:
        {
          imports = [ nixosModule.nixosModules.default ];

          virtualisation.vlans = [ 1 ];
          networking.useDHCP = false;

          my.router = {
            enable = true;

            pxe-boot = {
              enable = true;
              isoFolderPath = isoDir;
              nfs.enable = true;
            };

            configInterface.eth1 = {
              mac = null;
              dhcp.server = {
                id = 400;
                address = "${routerIp}/24";
                firstIP = 10;
                pxe-boot = {
                  enable = true;
                  defaultIso = isoName;
                  defaultScriptName = "";
                };
              };
              forwarding = true;
            };
          };
        };

      pxeClient =
        { lib, modulesPath, ... }:
        {
          imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

          virtualisation = {
            vlans = [ 1 ];
            # Firmware (UEFI/OVMF native PXE) instead of direct kernel boot,
            # and no disk: the only way to boot is from the network.
            useBootLoader = true;
            useEFIBoot = true;
            diskImage = null;
            mountHostNixStore = true;
            writableStore = false;
            memorySize = 3072;
            qemu.options = [
              "-boot"
              "order=n,menu=on"
            ];
            qemu.networkingOptions = lib.mkForce [
              "-netdev vde,id=pxenfs1,sock=\"$QEMU_VDE_SOCKET_1\""
              "-device virtio-net-pci,netdev=pxenfs1,mac=${clientMac},romfile=,bootindex=1"
            ];
          };

          networking = {
            useDHCP = false;
            firewall.enable = false;
          };

          boot.loader.grub.enable = false;
        };
    };

    testScript = ''
      router.start()
      router.wait_for_unit("multi-user.target")
      router.wait_for_unit("kea-dhcp4-server.service")
      router.wait_for_unit("pxe-boot-prepare.service")
      router.wait_for_unit("nfs-server.service")
      router.wait_for_unit("pxe-boot-nfs-exports.service")

      with subtest("The ISO is exported over NFS with its own fsid"):
          exports = router.succeed("exportfs -v")
          assert "${isoName}" in exports, f"ISO not exported:\n{exports}"
          assert "fsid=" in exports, f"export has no explicit fsid:\n{exports}"

      with subtest("The boot menu uses nfsiso= and not findiso="):
          menu = router.succeed("cat /srv/pxeboot/400/grub/grub.cfg")
          assert "nfsiso=${routerIp}:/run/pxe-boot/iso-mountpoint/${isoName}" in menu, menu
          assert "findiso=" not in menu, menu

      with subtest("RHEL with an installer image is exported and uses inst.repo=nfs:"):
          exports = router.succeed("exportfs -v")
          assert "${rhelNfsIsoName}" in exports, f"RHEL ISO not exported:\n{exports}"
          menu = router.succeed("cat /srv/pxeboot/400/grub/grub.cfg")
          entry = [l for l in menu.splitlines() if "inst.repo=" in l and "${rhelNfsIsoName}" in l]
          assert entry, menu
          # Trailing slash: RHEL's installer treats an nfs: repo ending in ".iso" as
          # an ISO file and mounts the parent directory, which is not exported.
          assert "inst.repo=nfs:${routerIp}:/run/pxe-boot/iso-mountpoint/${rhelNfsIsoName}/" in entry[0], entry[0]
          assert "inst.repo=http" not in entry[0], entry[0]

      with subtest("The installer's exact repo path mounts and shows the installer image"):
          # Same path and options the installer uses (NFS version 3, read-only).
          router.succeed(
              "mkdir -p /mnt/repo && mount -t nfs -o vers=3,nolock,ro "
              "${routerIp}:/run/pxe-boot/iso-mountpoint/${rhelNfsIsoName}/ /mnt/repo"
          )
          router.succeed("test -f /mnt/repo/images/install.img")
          router.succeed("umount /mnt/repo")

      with subtest("RHEL without an installer image stays on HTTP and is not exported"):
          exports = router.succeed("exportfs -v")
          assert "${rhelHttpIsoName}" not in exports, exports
          menu = router.succeed("cat /srv/pxeboot/400/grub/grub.cfg")
          entry = [l for l in menu.splitlines() if "inst.repo=" in l and "${rhelHttpIsoName}" in l]
          assert entry, menu
          assert "inst.repo=http://${routerIp}" in entry[0], entry[0]
          assert "inst.repo=nfs" not in entry[0], entry[0]

      with subtest("Client PXE-boots the ISO over NFS and reaches the beacon"):
          pxeClient.start()
          router.wait_until_succeeds(
              "journalctl -u nginx --no-pager | grep -q NIXOS-PXE-BOOT-SUCCESS",
              timeout=1500,
          )

      with subtest("The whole ISO was never downloaded over HTTP"):
          router.fail("journalctl -u nginx --no-pager | grep -q '/isos/'")

      try:
          pxeClient.crash()
      except BrokenPipeError:
          pass
    '';
  };
}
