{
  pkgs ? import <nixpkgs> { },
  nixosModule ? ../../.,
}:
###########################################################################
# PXE Boot Integration Test
###########################################################################
#
#   +----------------------------------------------------------------+
#   |  Test VMs (all on VLAN 1)                                      |
#   +----------------------------------------------------------------+
#   |                                                                |
#   |  +----------+  +--------+  +--------------+  +--------------+  |
#   |  |  router  |  | client |  | pxeClientUEFI|  | pxeClientBIOS|  |
#   |  | (server) |  |(tftp   |  |(diskless VM) |  |(diskless VM) |  |
#   |  |          |  | test)  |  |              |  |              |  |
#   |  | eth1:    |  | eth1   |  | ens8 (DHCP)  |  | ens8 (DHCP)  |  |
#   |  |192.168.  |  |        |  | PXE boot     |  | PXE boot     |  |
#   |  |  75.1/24 |  |        |  | enabled      |  | enabled      |  |
#   |  +----+-----+  +---+----+  +------+-------+  +------+-------+  |
#   |       |            |              |                 |          |
#   |       +------------+--------------+-----------------+          |
#   |                     VLAN 1 (virtual switch)                    |
#   +----------------------------------------------------------------+
#
# Network:
#   Router 192.168.75.1/24 — DHCP pool .10-.254
#   TFTP :69  HTTP :1337 (boot files + beacon)  HTTP :1338 (ISO files)
#
# Phases:
#   1. Router init -> start client + BIOS + UEFI VMs in background
#   2. Unit tests: fast-fail config checks (run while VMs PXE boot)
#   3. Integration: TFTP download from client VM
#   4. Progressive E2E checkpoints (each a subtest for localization):
#      TFTP -> HTTP boot files -> ISO download -> beacon per arch
#
# Beacon mechanism: the test ISO sends GET /NIXOS-PXE-BOOT-SUCCESS-<ts>
# to the router after booting.  darkhttpd logs it with the client IP,
# letting us attribute beacons to specific VMs via ARP table lookup.
#
# Timeouts: PXE chain 90s, boot files 600s, beacon 1200s (ISO download
# over the virtual network dominates at ~5-8 min).
#
###########################################################################
let
  # Shared constants — single source of truth for values used in both
  # Nix VM definitions and the Python test script.
  routerIp = "192.168.75.1";
  testIsoName = "nixos-pxe-test-x86_64.iso";
  pxeMacBIOS = "52:54:00:12:01:02";
  pxeMacUEFI = "52:54:00:12:01:03";

  ###########################################################################
  # Test ISO: custom NixOS that sends a beacon HTTP request after booting
  ###########################################################################
  testNixosIso =
    let
      nixosSystem = pkgs.nixos (
        {
          lib,
          pkgs,
          ...
        }:
        {
          imports = [ ../../modules/iso-builder ];

          pxe-boot-iso.enable = true;
          pxe-boot-iso.enableNetworkDownload = true;
          pxe-boot-iso.includeNetworkTools = true;
          pxe-boot-iso.includeDiskTools = false;
          pxe-boot-iso.includeHardwareTools = false;

          isoImage.isoName = lib.mkForce testIsoName;
          isoImage.volumeID = lib.mkForce "NIXOS_PXE_TEST";

          # Verbose console for debugging PXE boot issues
          boot.kernelParams = lib.mkBefore [
            "console=ttyS0,115200"
            "console=tty0"
            "loglevel=7"
            "rd.debug"
            "systemd.log_level=debug"
            "boot.trace"
          ];

          # Beacon: proves full E2E by making an HTTP request after boot.
          # See ./beacon.sh for the implementation.
          systemd.services.pxe-boot-beacon = {
            description = "PXE Boot Test Beacon";
            wantedBy = [ "multi-user.target" ];
            after = [
              "network-online.target"
              "NetworkManager-wait-online.service"
            ];
            wants = [ "network-online.target" ];

            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              TimeoutStartSec = 300;
              Environment = "ROUTER_IP=${routerIp}";
            };

            path = with pkgs; [
              curl
              iproute2
              networkmanager
              systemd
            ];
            script = builtins.readFile ./beacon.sh;
          };
        }
      );
    in
    nixosSystem.config.system.build.isoImage;

  ###########################################################################
  # Test ISO directory: real NixOS ISO + mock RHEL/Ubuntu for detection
  ###########################################################################
  dummyIsoDir =
    pkgs.runCommand "iso-directory"
      { nativeBuildInputs = [ pkgs.xorriso ]; }
      ''
        mkdir -p $out
        cp ${testNixosIso}/iso/*.iso $out/${testIsoName}

        # Mock RHEL ISO with expected directory structure
        mkdir -p rhel-root/images/pxeboot
        echo "Red Hat GPG Key" > rhel-root/RPM-GPG-KEY-redhat-release
        echo "Mock RHEL kernel" > rhel-root/images/pxeboot/vmlinuz
        echo "Mock RHEL initrd" > rhel-root/images/pxeboot/initrd.img
        xorriso -as mkisofs \
          -o $out/rhel-9.6-x86_64-dvd.iso \
          -V "RHEL-9-6-0-BaseOS-x86_64" \
          -r -J \
          rhel-root/

        # Mock Ubuntu ISO with expected directory structure
        mkdir -p ubuntu-root/casper
        echo "Mock Ubuntu squashfs" > ubuntu-root/casper/ubuntu-server-minimal.squashfs
        echo "Mock Ubuntu kernel" > ubuntu-root/casper/vmlinuz
        echo "Mock Ubuntu initrd" > ubuntu-root/casper/initrd
        xorriso -as mkisofs \
          -o $out/ubuntu-24.04-live-server-amd64.iso \
          -V "Ubuntu-Server 24.04 LTS amd64" \
          -r -J \
          ubuntu-root/
      '';

  testAutoinstallScript = pkgs.writeText "test.ks" ''
    # Test kickstart script
    lang en_US.UTF-8
    keyboard us
  '';

  ###########################################################################
  # PXE client VM base: diskless, must boot from network
  ###########################################################################
  # useBootLoader forces QEMU through firmware (UEFI/BIOS) instead of
  # direct kernel boot (-kernel/-initrd), which would bypass PXE entirely.
  # diskImage=null ensures no local boot fallback.  mountHostNixStore
  # provides the test framework shell via 9p (secondary to PXE boot).
  pxeboot_vm_base =
    { modulesPath, ... }:
    {
      imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

      virtualisation = {
        vlans = [ 1 ];
        useBootLoader = true;
        diskImage = null;
        mountHostNixStore = true;
        writableStore = false;
        memorySize = 2048;
        qemu.options = [ "-boot" "order=n,menu=on" ];
      };

      networking = {
        useDHCP = false;
        firewall.enable = false;
      };

      # No disk, no bootloader — firmware falls back to network boot
      boot.loader.grub.enable = false;

      fileSystems."/" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "mode=0755" "size=2G" ];
      };
    };
in
pkgs.testers.nixosTest {
  name = "router-pxe-boot";
  skipLint = false;

  nodes = {
    # Router: DHCP + TFTP + HTTP PXE boot server
    router =
      { pkgs, ... }:
      {
        imports = [ nixosModule.nixosModules.default ];

        virtualisation.vlans = [ 1 ];
        networking.useDHCP = false;

        boot.kernelModules = [ "loop" ]; # for ISO mounting

        my.router = {
          enable = true;

          pxe-boot = {
            enable = true;
            isoFolderPath = dummyIsoDir;
            autoinstall = {
              "ubuntu-24.04-live-server-amd64.iso" = [
                { scriptName = "minimal.ks"; script = testAutoinstallScript; }
                { scriptName = "advanced.ks"; script = "# Advanced config\nnetwork --bootproto=dhcp"; }
              ];
              "rhel-9.6-x86_64-dvd.iso" = [
                { scriptName = "server.ks"; script = testAutoinstallScript; }
              ];
              "${testIsoName}" = [ ];
            };
          };

          configInterface = [
            {
              name = "eth1";
              mac = null;
              dhcp = {
                server = {
                  id = 200;
                  gateway = "${routerIp}/24";
                  firstIP = 10;
                  pxe-boot = {
                    enable = true;
                    defaultIso = testIsoName;
                    defaultScriptName = "";
                  };
                };
              };
              forwarding = true;
            }
          ];
        };
      };

    # Simple TFTP test client (static IP, no DHCP)
    client =
      { pkgs, ... }:
      {
        virtualisation.vlans = [ 1 ];
        networking.useDHCP = false;
        networking.firewall.enable = false;
        environment.systemPackages = with pkgs; [ tftp-hpa jq dhcpcd ];
      };

    # UEFI PXE: OVMF firmware, romfile="" disables iPXE so OVMF uses
    # its native PXE stack and sends DHCP option 93 (client arch).
    pxeClientUEFI =
      { lib, ... }:
      {
        imports = [ pxeboot_vm_base ];
        virtualisation = {
          useEFIBoot = true;
          qemu.networkingOptions = lib.mkForce [
            "-netdev vde,id=pxeuefi1,sock=\"$QEMU_VDE_SOCKET_1\""
            "-device virtio-net-pci,netdev=pxeuefi1,mac=${pxeMacUEFI},romfile=,bootindex=1"
          ];
        };
      };

    # BIOS PXE: SeaBIOS + explicit iPXE ROM for reliable network boot.
    pxeClientBIOS =
      { pkgs, lib, ... }:
      {
        imports = [ pxeboot_vm_base ];
        virtualisation = {
          useEFIBoot = false;
          qemu.networkingOptions = lib.mkForce [
            "-netdev vde,id=pxebios1,sock=\"$QEMU_VDE_SOCKET_1\""
            "-device virtio-net-pci,netdev=pxebios1,mac=${pxeMacBIOS},romfile=${pkgs.qemu}/share/qemu/pxe-virtio.rom,bootindex=1"
          ];
        };
      };
  };

  testScript =
    # python
    ''
      import json
      import time
      import re
      from collections import namedtuple

      ###########################################################################
      # Helpers
      ###########################################################################

      JournalLog = namedtuple("JournalLog", ["text", "lines"])

      DHCP_UNIT = "kea-dhcp4-server.service"
      TFTP_UNIT = "pxe-boot-tftp-server-for-interface-eth1.service"
      HTTP_BOOT_UNIT = "pxe-boot-http-server.service"    # port 1337
      HTTP_ISO_UNIT = "pxe-boot-http-server2.service"    # port 1338

      BIOS_MAC = "${pxeMacBIOS}"
      UEFI_MAC = "${pxeMacUEFI}"

      def journal_mark(machine):
          """Capture current journal cursor."""
          return machine.succeed(
              "journalctl --no-pager -n 0 --show-cursor | sed -n 's/^-- cursor: //p'"
          ).strip()

      def journal_since(machine, cursor, unit=None):
          """Get journal entries since cursor, optionally filtered by unit."""
          cmd = f"journalctl --no-pager --after-cursor='{cursor}'"
          if unit:
              cmd += f" -u '{unit}'"
          text = machine.succeed(cmd)
          lines = [l for l in text.strip().splitlines() if l]
          return JournalLog(text=text, lines=lines)

      def journal_wait(machine, cursor, pattern, unit=None, timeout=120, interval=5):
          """Poll journal until pattern appears. Raises TimeoutError on failure."""
          for _ in range(timeout // interval):
              result = journal_since(machine, cursor, unit)
              if re.search(pattern, result.text):
                  return result
              time.sleep(interval)
          raise TimeoutError(f"Pattern '{pattern}' not found in journal after {timeout}s")

      def lookup_ip_by_mac(arp_output, mac):
          """Find IP for a MAC address in 'ip neigh' output."""
          for line in arp_output.split('\n'):
              if mac in line.lower():
                  return line.split()[0]
          return None

      ###########################################################################
      # Phase 1: Router init + start background VMs
      ###########################################################################

      router.start()
      router.wait_for_unit("multi-user.target")
      router.wait_for_unit("systemd-networkd.service")
      router.wait_for_unit("kea-dhcp4-server.service")
      router.wait_for_unit("pxe-boot-prepare.service")

      status = router.succeed("systemctl show -p ActiveState -p Result pxe-boot-main-script.service")
      assert "Result=success" in status, f"pxe-boot-main-script failed: {status}"

      # Start all background VMs — they PXE boot while unit tests run
      e2e_mark = journal_mark(router)
      pxeClientBIOS.start(allow_reboot=False)
      pxeClientUEFI.start(allow_reboot=False)
      client.start()

      ###########################################################################
      # Phase 2: Unit tests (fast-fail config checks)
      ###########################################################################
      # client + pxeClientBIOS + pxeClientUEFI boot in parallel during this phase.

      with subtest("TFTP service is running"):
          router.succeed(f"systemctl is-active {TFTP_UNIT}")

      with subtest("Router interface has correct IP"):
          addr_info = json.loads(router.succeed("ip --json addr show eth1"))
          ipv4_addrs = [
              a for a in addr_info[0]["addr_info"]
              if a.get("local") == "${routerIp}" and a.get("prefixlen") == 24
          ]
          assert len(ipv4_addrs) == 1, \
              f"Expected ${routerIp}/24 on eth1, got: {addr_info[0]['addr_info']}"

      with subtest("GRUB boot files are present"):
          for name in ["grubx64.efi", "grub.pxe", "grubaa64.efi"]:
              size = int(router.succeed(f"stat -c %s /srv/pxeboot/200/{name}").strip())
              assert size > 0, f"{name} is empty (0 bytes)"
              router.log(f"  {name}: {size} bytes")

      # Read once, used by multiple subtests below
      grub_cfg = router.succeed("cat /srv/pxeboot/200/grub/grub.cfg")
      router.succeed("cp /srv/pxeboot/200/grub/grub.cfg /tmp/xchg/grub.cfg")

      with subtest("GRUB config includes all detected ISOs"):
          assert grub_cfg, "GRUB config is empty"
          assert "Reload Grub" in grub_cfg, "Missing 'Reload Grub' entry"
          for keyword in ["ubuntu", "rhel", "nixos-pxe-test"]:
              assert keyword.lower() in grub_cfg.lower(), \
                  f"GRUB config missing '{keyword}'"

      with subtest("NixOS ISO is default boot entry"):
          default_match = re.search(r'set default=(\d+)', grub_cfg)
          assert default_match, "No 'set default=' in GRUB config"
          default_idx = int(default_match.group(1))

          menu_entries = re.findall(r'menuentry\s+"([^"]+)"', grub_cfg)
          assert default_idx < len(menu_entries), \
              f"Default index {default_idx} out of range ({len(menu_entries)} entries)"
          assert "nixos-pxe-test" in menu_entries[default_idx].lower(), \
              f"Default entry is '{menu_entries[default_idx]}', expected NixOS ISO"

          for i, entry in enumerate(menu_entries):
              marker = " <-- DEFAULT" if i == default_idx else ""
              router.log(f"  [{i}] {entry}{marker}")

      with subtest("NixOS ISO is mounted and served via HTTP"):
          router.succeed("test -d /run/pxe-boot/iso-mountpoint/${testIsoName}")
          boot_contents = router.succeed("ls /run/pxe-boot/iso-mountpoint/${testIsoName}/boot/")
          assert "nix" in boot_contents or "bzImage" in boot_contents, \
              f"Unexpected ISO boot dir contents: {boot_contents}"
          router.succeed("curl -s -f http://${routerIp}:1338/${testIsoName} > /dev/null")

      with subtest("Kea DHCP config has PXE client classes"):
          service_info = router.succeed("systemctl cat kea-dhcp4-server.service")
          config_match = re.search(r'-c\s+([^\s]+)', service_info)
          config_path = config_match.group(1) if config_match else "/etc/kea/kea-dhcp4.conf"

          kea_json = json.loads(router.succeed(f"cat {config_path}"))
          class_names = [c["name"] for c in kea_json["Dhcp4"]["client-classes"]]

          for keyword in ["iPXE", "BIOS", "aarch64"]:
              assert any(keyword in n for n in class_names), \
                  f"No client class containing '{keyword}' in: {class_names}"
          assert any("UEFI" in n and "x86_64" in n for n in class_names), \
              f"No UEFI x86_64 class in: {class_names}"

      with subtest("Autoinstall scripts are deployed"):
          ubuntu_ks = router.succeed(
              "cat /run/pxe-boot/unattented-install/ubuntu-24.04-live-server-amd64.iso/minimal.ks"
          )
          assert "lang en_US.UTF-8" in ubuntu_ks, f"Unexpected content: {ubuntu_ks[:200]}"
          assert "keyboard us" in ubuntu_ks, f"Missing 'keyboard us': {ubuntu_ks[:200]}"

          advanced_ks = router.succeed(
              "cat /run/pxe-boot/unattented-install/ubuntu-24.04-live-server-amd64.iso/advanced.ks"
          )
          assert "network --bootproto=dhcp" in advanced_ks, f"Unexpected: {advanced_ks[:200]}"

          rhel_ks = router.succeed(
              "cat /run/pxe-boot/unattented-install/rhel-9.6-x86_64-dvd.iso/server.ks"
          )
          assert "lang en_US.UTF-8" in rhel_ks, f"Unexpected: {rhel_ks[:200]}"

      ###########################################################################
      # Phase 3: TFTP integration test
      ###########################################################################

      with subtest("TFTP download from client VM"):
          client.wait_for_unit("multi-user.target")
          client.succeed("ip addr add 192.168.75.50/24 dev eth1")
          client.succeed("ip link set eth1 up")
          client.sleep(2)  # link-layer convergence

          client.succeed("ping -c 3 ${routerIp}")

          client.succeed("tftp ${routerIp} -c get grubx64.efi /tmp/grubx64.efi")
          size = int(client.succeed("stat -c %s /tmp/grubx64.efi").strip())
          assert size > 0, f"grubx64.efi is empty ({size} bytes)"
          router.log(f"  grubx64.efi: {size} bytes")

          client.succeed("tftp ${routerIp} -c get grub/grub.cfg /tmp/grub.cfg")
          fetched_cfg = client.succeed("cat /tmp/grub.cfg")
          assert "Reload Grub" in fetched_cfg, \
              f"Fetched GRUB config missing 'Reload Grub': {fetched_cfg[:200]}"

          client.shutdown()

      ###########################################################################
      # Phase 4: Progressive E2E checkpoints
      ###########################################################################
      # Both VMs have been PXE booting since Phase 1. Each checkpoint is a
      # separate subtest so failures pinpoint the exact stage.

      with subtest("BIOS PXE: GRUB bootloader served via TFTP"):
          journal_wait(router, e2e_mark, r"grub\.pxe", unit=TFTP_UNIT,
                       timeout=90, interval=10)

      with subtest("UEFI PXE: GRUB bootloader served via TFTP"):
          journal_wait(router, e2e_mark, r"grubx64\.efi", unit=TFTP_UNIT,
                       timeout=90, interval=10)

      # Look up DHCP-assigned IPs via ARP for beacon attribution
      arp_output = router.succeed("ip neigh show dev eth1").strip()
      bios_ip = lookup_ip_by_mac(arp_output, BIOS_MAC)
      uefi_ip = lookup_ip_by_mac(arp_output, UEFI_MAC)
      router.log(f"DHCP IPs - BIOS: {bios_ip or 'unknown'}, UEFI: {uefi_ip or 'unknown'}")

      with subtest("E2E: Kernel/initrd download detected"):
          journal_wait(router, e2e_mark, r"bzImage", unit=HTTP_BOOT_UNIT,
                       timeout=600, interval=15)

      with subtest("E2E: ISO download detected"):
          journal_wait(router, e2e_mark, r"nixos-pxe-test.*\.iso", unit=HTTP_ISO_UNIT,
                       timeout=600, interval=15)

      def wait_for_beacon(label, ip):
          """Wait for a NIXOS-PXE-BOOT-SUCCESS beacon from the given IP."""
          if ip:
              pattern = rf"{re.escape(ip)}.*NIXOS-PXE-BOOT-SUCCESS"
          else:
              router.log(f"WARN: {label} IP unknown, matching any beacon")
              pattern = r"NIXOS-PXE-BOOT-SUCCESS"
          journal_wait(router, e2e_mark, pattern, unit=HTTP_BOOT_UNIT,
                       timeout=1200, interval=20)

      try:
          with subtest("BIOS E2E: Beacon received"):
              wait_for_beacon("BIOS", bios_ip)

          with subtest("UEFI E2E: Beacon received"):
              wait_for_beacon("UEFI", uefi_ip)
      finally:
          # Collect service logs for post-mortem (runs even on timeout)
          router.log("=== Final Service Logs ===")
          for unit_name, label in [
              (HTTP_BOOT_UNIT, "HTTP Boot (1337)"),
              (HTTP_ISO_UNIT, "HTTP ISO (1338)"),
              (DHCP_UNIT, "DHCP"),
              (TFTP_UNIT, "TFTP"),
          ]:
              unit_log = journal_since(router, e2e_mark, unit=unit_name)
              router.log(f"--- {label} ---")
              router.log(unit_log.text)

          # Terminate PXE VMs (crash() may raise BrokenPipeError if the
          # VM already shut down after sending its beacon)
          for vm in [pxeClientBIOS, pxeClientUEFI]:
              try:
                  vm.crash()
              except BrokenPipeError:
                  pass
    '';
}
