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

  isoDir = pkgs.runCommand "nixos-nfs-test-iso-directory" { } ''
    mkdir -p $out
    cp ${testIso}/iso/*.iso $out/${isoName}
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
