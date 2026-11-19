{
  pkgs ? import <nixpkgs> { },
  nixosModule ? ../../.,
}:
###########################################################################
# Picky PXE client: boot file lookup the way some real firmware does it
###########################################################################
#
# The other PXE VM tests boot QEMU's firmware (OVMF, iPXE), which reads DHCP
# option 67 by its length field and so accepts any offer that is valid by the
# RFC. Some real UEFI firmware instead copies the option up to the first NUL
# byte; with an unterminated option 67 it reads on into the DHCP END marker and
# requests "bootx64.efi\xff" over TFTP (PXE-E23, seen on real hardware).
# QEMU cannot be made to behave like that firmware, so ./picky-pxe-client.py
# imitates it: DISCOVER, pick the boot file that way, TFTP RRQ, fail on error.
#
# Covers the x86 classes (BIOS and UEFI x64). aarch64 still sends option 67
# (see nixosModule/config.nix) and is not exercised.
###########################################################################
let
  mockIsoName = "rhel-9.6-x86_64-dvd.iso";

  mockIsoDir =
    pkgs.runCommand "picky-client-iso-directory" { nativeBuildInputs = [ pkgs.xorriso ]; }
      ''
        mkdir -p $out
        mkdir -p rhel-root/images/pxeboot
        echo "Red Hat GPG Key" > rhel-root/RPM-GPG-KEY-redhat-release
        echo "Mock RHEL kernel" > rhel-root/images/pxeboot/vmlinuz
        echo "Mock RHEL initrd" > rhel-root/images/pxeboot/initrd.img
        xorriso -as mkisofs \
          -o $out/${mockIsoName} \
          -V "RHEL-9-6-0-BaseOS-x86_64" \
          -r -J \
          rhel-root/
      '';

  pickyClient = pkgs.writers.writePython3Bin "picky-pxe-client" {
    # Long lines are fine in a test script.
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./picky-pxe-client.py);
in
{
  vm = pkgs.testers.nixosTest {
    name = "router-pxe-boot-picky-client";
    skipLint = false;

    nodes = {
      router =
        { ... }:
        {
          imports = [ nixosModule.nixosModules.default ];

          virtualisation.vlans = [ 1 ];
          networking.useDHCP = false;

          my.router = {
            enable = true;

            pxe-boot = {
              enable = true;
              isoFolderPath = mockIsoDir;
            };

            configInterface.eth1 = {
              mac = null;
              dhcp.server = {
                id = 500;
                address = "192.168.95.1/24";
                firstIP = 10;
                pxe-boot = {
                  enable = true;
                  defaultIso = mockIsoName;
                  defaultScriptName = "";
                };
              };
              forwarding = true;
            };
          };
        };

      client =
        { ... }:
        {
          virtualisation.vlans = [ 1 ];
          networking.useDHCP = false;
          networking.firewall.enable = false;
          # The offer comes from a subnet the (addressless) client has no
          # route to; strict reverse-path filtering would drop it. Real PXE
          # firmware does not apply that filter.
          boot.kernel.sysctl = {
            "net.ipv4.conf.all.rp_filter" = 0;
            "net.ipv4.conf.default.rp_filter" = 0;
          };
          environment.systemPackages = [
            pickyClient
            pkgs.iproute2
          ];
        };
    };

    testScript = ''
      router.start()
      router.wait_for_unit("multi-user.target")
      router.wait_for_unit("kea-dhcp4-server.service")
      router.wait_for_unit("pxe-boot-prepare.service")
      router.wait_for_unit("pxe-boot-tftp-server-for-interface-eth1.service")
      # The boot files are copied into the TFTP root by a oneshot unit.
      router.wait_until_succeeds("test -f /srv/pxeboot/500/bootx64.efi && test -f /srv/pxeboot/500/grub.pxe")

      client.start()
      client.wait_for_unit("multi-user.target")

      with subtest("UEFI x64 client gets bootx64.efi"):
          out = client.succeed("picky-pxe-client eth1 7")
          assert "boot_file=b'bootx64.efi'" in out, out
          assert "tftp=OK" in out, out

      with subtest("BIOS client gets /grub.pxe"):
          out = client.succeed("picky-pxe-client eth1 0")
          assert "boot_file=b'/grub.pxe'" in out, out
          assert "tftp=OK" in out, out
    '';
  };
}
