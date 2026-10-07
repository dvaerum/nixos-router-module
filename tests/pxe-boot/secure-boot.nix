{
  pkgs ? import <nixpkgs> { },
  nixosModule ? ../../.,
}:
###########################################################################
# Secure Boot PXE Boot Integration Test
###########################################################################
#
#   +------------------------------------------------------------------+
#   |  router (vlans 1 + 2)                                            |
#   |    eth1: 192.168.80.1/24  --(vlan 1)--  goodClient (UEFI + SB)    |
#   |    eth2: 192.168.81.1/24  --(vlan 2)--  badClient  (UEFI + SB)    |
#   +------------------------------------------------------------------+
#
# Both clients boot UEFI firmware with Secure Boot enabled and the
# standard Microsoft-enrolled key database (`pkgs.OVMFFull.variablesMs`
# -- confirmed via nixpkgs' own OVMF derivation: `EnrollDefaultKeys.efi`
# seeds `db` with the real Microsoft UEFI CA 2011 cert, the same cert
# that signs the real-world shim binary served here). This is the same
# trust store real off-the-shelf hardware ships with.
#
#   goodClient fetches the pristine `bootx64.efi` (Microsoft-signed
#   shim) -> bootx64.efi verifies and chain-loads the pristine
#   `grubx64.efi` (Canonical-signed) -> real GRUB menu renders.
#
#   badClient's `grubx64.efi` is corrupted (single byte flipped deep in
#   the code section, confirmed via `osslsigncode verify` to break the
#   embedded Authenticode digest without touching the PE/DOS headers)
#   AFTER staging but BEFORE the client boots -> shim's signature check
#   fails -> shim shows its own rejection dialog, "Verification failed:
#   (0x1A) Security Violation", instead of booting grub (confirmed
#   empirically against a real OVMF+signed-shim+Secure-Boot chain: this
#   exact text is what shim renders immediately on a failed Authenticode
#   verification, before any MokManager interaction).
#
# Both checkpoints are read via OCR (`wait_for_text`): GRUB's prebuilt
# UEFI binaries (Ubuntu's own netboot build) are not guaranteed to use
# the plain UEFI-console terminal (which would mirror to the serial
# console test helper) -- OCR reads the actual rendered framebuffer
# regardless of which GRUB terminal driver is in effect.
###########################################################################
let
  mockIsoName = "rhel-9.6-x86_64-dvd.iso";

  mockIsoDir =
    pkgs.runCommand "secure-boot-iso-directory" { nativeBuildInputs = [ pkgs.xorriso ]; }
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

  goodMac = "52:54:00:bb:01:02";
  badMac = "52:54:00:bb:02:02";

  # Shared base for both Secure-Boot PXE clients: UEFI + Secure Boot
  # enabled, Microsoft-default key database pre-enrolled. No disk --
  # firmware must fall through to the network boot stack. Unlike
  # `pxeboot_vm_base` in default.nix, this test never proceeds past the
  # GRUB/MokManager screen, so none of the large-tmpfs/findiso= plumbing
  # from that base is needed here.
  secureBootClientBase = { modulesPath, ... }: {
    imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

    virtualisation = {
      useEFIBoot = true;
      efi.OVMF = pkgs.OVMFFull.fd;
      efi.variables = pkgs.OVMFFull.variablesMs;
      # `keepVariables` defaults to `cfg.useBootLoader` (true here), which
      # seeds $NIX_EFI_VARS from the make-disk-image-generated template
      # instead of `cfg.efi.variables` above (see qemu-vm.nix: the
      # `keepVariables` branch copies "${systemImage}/efi-vars.fd", NOT
      # our override -- confirmed empirically: both clients booted a
      # tampered grubx64.efi WITHOUT any Secure Boot rejection, because
      # the disk-image's own template is still in Setup Mode with no PK
      # enrolled, so shim's secure_mode() reads false and skips all
      # verification). Disabling this is safe here: these are diskless
      # findiso= clients, there is no `switch-to-configuration`-driven EFI
      # variable write to preserve across a reboot that never happens.
      efi.keepVariables = false;
      useBootLoader = true;
      diskImage = null;
      mountHostNixStore = true;
      writableStore = false;
      memorySize = 1024;
      qemu.options = [
        "-boot"
        "order=n,menu=on"
      ];
    };

    networking = {
      useDHCP = false;
      firewall.enable = false;
    };

    boot.loader.grub.enable = false;
  };
in
{
  vm = pkgs.testers.nixosTest {
    name = "router-pxe-boot-secure-boot";
    skipLint = false;
    enableOCR = true;

    nodes = {
      router = { pkgs, ... }: {
        imports = [ nixosModule.nixosModules.default ];

        virtualisation.vlans = [
          1
          2
        ];
        networking.useDHCP = false;

        # Diagnostics only (see the "Tamper..." subtest below) -- not
        # needed for the PXE boot mechanism itself.
        environment.systemPackages = with pkgs; [
          tftp-hpa
          osslsigncode
        ];

        my.router = {
          enable = true;

          pxe-boot = {
            enable = true;
            isoFolderPath = mockIsoDir;
          };

          configInterface = {
            eth1 = {
              mac = null;
              dhcp.server = {
                id = 300;
                address = "192.168.80.1/24";
                firstIP = 10;
                pxe-boot = {
                  enable = true;
                  defaultIso = mockIsoName;
                  defaultScriptName = "";
                };
              };
              forwarding = true;
            };

            eth2 = {
              mac = null;
              dhcp.server = {
                id = 301;
                address = "192.168.81.1/24";
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
      };

      # UEFI + Secure Boot, pristine chain: shim -> grub -> real menu.
      goodClient = { lib, ... }: {
        imports = [ secureBootClientBase ];
        virtualisation.vlans = [ 1 ];
        virtualisation.qemu.networkingOptions = lib.mkForce [
          "-netdev vde,id=goodsb1,sock=\"$QEMU_VDE_SOCKET_1\""
          "-device virtio-net-pci,netdev=goodsb1,mac=${goodMac},romfile=,bootindex=1"
        ];
      };

      # UEFI + Secure Boot, tampered grubx64.efi: shim rejects it with a
      # "Security Violation" error instead of booting the real menu.
      badClient = { lib, ... }: {
        imports = [ secureBootClientBase ];
        virtualisation.vlans = [ 2 ];
        virtualisation.qemu.networkingOptions = lib.mkForce [
          "-netdev vde,id=badsb1,sock=\"$QEMU_VDE_SOCKET_2\""
          "-device virtio-net-pci,netdev=badsb1,mac=${badMac},romfile=,bootindex=1"
        ];
      };
    };

    testScript =
      # python
      ''
        router.start()
        router.wait_for_unit("multi-user.target")
        router.wait_for_unit("kea-dhcp4-server.service")
        router.wait_for_unit("pxe-boot-prepare.service")

        status = router.succeed(
            "systemctl show -p ActiveState -p Result pxe-boot-main-script.service"
        )
        assert "Result=success" in status, f"pxe-boot-main-script failed: {status}"

        with subtest("Tamper with badClient's interface grubx64.efi (post-stage, pre-boot)"):
            # Offset ~1,000,000 of a ~2.4MB file: well inside the PE code
            # section, well past the DOS/PE headers (confirmed via
            # `osslsigncode verify` -- breaks the embedded Authenticode
            # digest cleanly, no PE/DOS parse error).
            good_sum_before = router.succeed(
                "sha256sum /srv/pxeboot/300/grubx64.efi /srv/pxeboot/301/grubx64.efi"
            )
            router.log(f"Before tamper:\n{good_sum_before}")

            router.succeed(
                "dd if=/dev/zero of=/srv/pxeboot/301/grubx64.efi "
                "bs=1 seek=1000000 count=4 conv=notrunc"
            )
            size = int(router.succeed("stat -c %s /srv/pxeboot/301/grubx64.efi").strip())
            assert size > 0, "tampered grubx64.efi is unexpectedly empty"

            sums_after = router.succeed(
                "sha256sum /srv/pxeboot/300/grubx64.efi /srv/pxeboot/301/grubx64.efi"
            )
            router.log(f"After tamper:\n{sums_after}")
            good_hash = sums_after.splitlines()[0].split()[0]
            bad_hash = sums_after.splitlines()[1].split()[0]
            assert good_hash != bad_hash, (
                "Tamper had no effect -- eth1 and eth2 grubx64.efi still "
                f"identical after dd:\n{sums_after}"
            )

            # Confirm the Authenticode digest itself is actually broken
            # (not just that the bytes moved), independent of any TFTP
            # serving layer, and that the pristine copy is NOT broken.
            good_verify = router.succeed(
                "osslsigncode verify /srv/pxeboot/300/grubx64.efi 2>&1 || true"
            )
            bad_verify = router.succeed(
                "osslsigncode verify /srv/pxeboot/301/grubx64.efi 2>&1 || true"
            )
            assert "MISMATCH" not in good_verify, (
                f"pristine grubx64.efi unexpectedly shows a digest MISMATCH:\n{good_verify}"
            )
            assert "MISMATCH" in bad_verify, (
                f"tampered grubx64.efi does NOT show a digest MISMATCH -- "
                f"corruption did not actually break the Authenticode digest:\n{bad_verify}"
            )

            # Confirm what's actually served over the wire (not just what's
            # on disk) matches the tampered file -- rules out any TFTP
            # daemon-level caching of the pre-tamper content.
            router.succeed(
                "tftp 192.168.81.1 -c get grubx64.efi /tmp/eth2-grubx64-wire.efi"
            )
            wire_hash = router.succeed(
                "sha256sum /tmp/eth2-grubx64-wire.efi"
            ).split()[0]
            assert wire_hash == bad_hash, (
                f"TFTP served a DIFFERENT grubx64.efi than what's on disk -- "
                f"wire hash {wire_hash} != on-disk hash {bad_hash} "
                "(possible daemon-level caching)"
            )


        goodClient.start(allow_reboot=False)
        badClient.start(allow_reboot=False)

        with subtest("Good client: Secure Boot chain verifies, real GRUB menu renders"):
            goodClient.wait_for_text("(?i)rhel", timeout=120)

        with subtest("Bad client: tampered grubx64.efi rejected by shim's Secure Boot check"):
            badClient.wait_for_text("(?i)security violation", timeout=120)
            # Negative control: the real GRUB menu (which would render the
            # mock ISO's title) must never have appeared for this client.
            screen = badClient.get_screen_text()
            assert "rhel" not in screen.lower(), (
                f"badClient rendered the real GRUB menu despite a tampered "
                f"grubx64.efi -- Secure Boot verification did not reject it. "
                f"Screen text: {screen!r}"
            )

        for vm in [goodClient, badClient]:
            try:
                vm.crash()
            except BrokenPipeError:
                pass
      '';
  };
}
