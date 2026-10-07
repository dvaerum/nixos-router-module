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
#   TFTP :69  HTTP :1337 (boot files + beacon + ISO files, one nginx vhost)
#
# Phases:
#   1. Router init -> start client + BIOS + UEFI VMs in background
#   2. Unit tests: fast-fail config checks (run while VMs PXE boot)
#   3. Integration: TFTP download from client VM
#   4. Progressive E2E checkpoints (each a subtest for localization):
#      TFTP -> HTTP boot files -> ISO download -> beacon per arch
#
# Beacon mechanism: the test ISO sends GET /NIXOS-PXE-BOOT-SUCCESS-<ts>
# to the router after booting. nginx logs it (access_log routed to
# stdout/journal) with the client IP, letting us attribute beacons to
# specific VMs via ARP table lookup.
#
# Timeouts: PXE chain 90s, boot files 600s, beacon 1200s (ISO download
# over the virtual network dominates at ~5-8 min).
#
###########################################################################
let
  # Shared constants — single source of truth for values used in both
  # Nix VM definitions and the Python test script.
  routerIp = "192.168.75.1";
  # Must match nixosModule/config-tftp.nix's own internal `httpPort`
  # binding -- that value isn't exposed as a NixOS option today, so this
  # is the closest to a single source of truth achievable from a test
  # file; previously this port number was hardcoded independently in 3
  # separate places in this file plus beacon.sh, with no connection
  # between any of them.
  testHttpPort = 1337;
  testIsoName = "nixos-pxe-test-x86_64.iso";
  pxeMacBIOS = "52:54:00:12:01:02";
  pxeMacUEFI = "52:54:00:12:01:03";
  # Regression: a reservation with an IP OUTSIDE the DHCP pool (.10-.254).
  # Reserved-IP clients do not draw from the pool, so PXE boot classes that are
  # only required at the POOL level never fire for them -> their DHCP offer
  # carries no next-server/boot-file-name -> UEFI/OVMF fails with
  # "PXE-E16: No valid offer received". The pxe classes must therefore be
  # required at the SUBNET level. See the "reserved-IP client" subtest below.
  reservedPxeMac = "52:54:00:12:01:09";
  reservedPxeIp = "192.168.75.5"; # < firstIP (.10) => outside the pool

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
              Environment = "ROUTER_IP=${routerIp} HTTP_PORT=${toString testHttpPort}";
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
  dummyIsoDir = pkgs.runCommand "iso-directory" { nativeBuildInputs = [ pkgs.xorriso ]; } ''
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
  pxeboot_vm_base = { modulesPath, ... }: {
    imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

    virtualisation = {
      vlans = [ 1 ];
      useBootLoader = true;
      diskImage = null;
      mountHostNixStore = true;
      writableStore = false;
      memorySize = 2048;
      qemu.options = [
        "-boot"
        "order=n,menu=on"
      ];
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
      options = [
        "mode=0755"
        "size=2G"
      ];
    };
  };
in
{
  vm = pkgs.testers.nixosTest {
    name = "router-pxe-boot";
    skipLint = false;

    nodes = {
      # Router: DHCP + TFTP + HTTP PXE boot server
      router = { pkgs, ... }: {
        imports = [ nixosModule.nixosModules.default ];

        virtualisation.vlans = [
          1
          2
          3
          4
          5
        ];
        networking.useDHCP = false;

        boot.kernelModules = [ "loop" ]; # for ISO mounting

        # Lets the router itself fetch from its own standalone TFTP server
        # (eth3, below) to verify it actually serves files end-to-end.
        environment.systemPackages = [ pkgs.tftp-hpa ];

        my.router = {
          enable = true;

          pxe-boot = {
            enable = true;
            isoFolderPath = dummyIsoDir;
            autoinstall = {
              "ubuntu-24.04-live-server-amd64.iso" = [
                {
                  scriptName = "minimal.ks";
                  script = testAutoinstallScript;
                }
                {
                  scriptName = "advanced.ks";
                  script = "# Advanced config\nnetwork --bootproto=dhcp";
                }
              ];
              "rhel-9.6-x86_64-dvd.iso" = [
                {
                  scriptName = "server.ks";
                  script = testAutoinstallScript;
                }
              ];
              "${testIsoName}" = [ ];
            };
          };

          configInterface = {
            eth1 = {
              mac = null;
              dhcp = {
                server = {
                  id = 200;
                  address = "${routerIp}/24";
                  firstIP = 10;
                  # Regression fixture: a reservation OUTSIDE the pool (.5 < firstIP
                  # .10). Exercises that PXE options reach reserved-IP clients.
                  reservations = {
                    "${reservedPxeMac}" = {
                      ip-address = reservedPxeIp;
                    };
                  };
                  pxe-boot = {
                    enable = true;
                    defaultIso = testIsoName;
                    defaultScriptName = "";
                  };
                };
              };
              forwarding = true;
            };

            # `tftpServer = false` regression fixture: no PXE client attached
            # here -- this subnet only exists to verify that grub/iPXE files
            # still get staged to disk (the promise made in the `warnings`
            # text) even though no TFTP server is running for it.
            eth2 = {
              mac = null;
              dhcp = {
                server = {
                  id = 201;
                  address = "192.168.76.1/24";
                  firstIP = 10;
                  tftpServer = false;
                  pxe-boot = {
                    enable = true;
                    defaultIso = testIsoName;
                    defaultScriptName = "";
                  };
                };
              };
              forwarding = true;
            };

            # Standalone `tftpServer` regression fixture: no `pxe-boot` at all
            # on this interface (default `false`) -- proves the TFTP server
            # can run entirely independently of PXE boot.
            eth3 = {
              mac = null;
              dhcp = {
                server = {
                  id = 202;
                  address = "192.168.77.1/24";
                  firstIP = 10;
                  tftpServer = true;
                };
              };
              forwarding = true;
            };

            # `disableTftpServerWarning` regression fixture: opted out of the
            # TFTP server like eth2, but silences the reminder warning. Proves
            # only that file-staging is unaffected -- the suppression itself
            # is proven by the separate `tftpWarningsCheck` pure-eval check
            # below (a different, minimal fixture, not this VM).
            eth4 = {
              mac = null;
              dhcp = {
                server = {
                  id = 203;
                  address = "192.168.78.1/24";
                  firstIP = 10;
                  tftpServer = false;
                  pxe-boot = {
                    enable = true;
                    disableTftpServerWarning = true;
                    defaultIso = testIsoName;
                    defaultScriptName = "";
                  };
                };
              };
              forwarding = true;
            };

            # `tftpServerRoot` regression fixture: overrides the global
            # `tftpServer.root` for just this interface. Proves the override
            # reaches BOTH halves that must agree on it -- the Rust
            # pxe-boot-prepare binary (grub.cfg) and the Nix-generated
            # rsync/atftpd (grub/iPXE binaries, main.ipxe) -- since a root
            # known to only one of them would silently break PXE boot here.
            eth5 = {
              mac = null;
              dhcp = {
                server = {
                  id = 204;
                  address = "192.168.79.1/24";
                  firstIP = 10;
                  tftpServerRoot = "/srv/custom-tftp-root";
                  pxe-boot = {
                    enable = true;
                    defaultIso = testIsoName;
                    defaultScriptName = "";
                  };
                };
              };
              forwarding = true;
            };
          };
        };
      };

      # Simple TFTP test client (static IP, no DHCP)
      client = { pkgs, ... }: {
        virtualisation.vlans = [ 1 ];
        networking.useDHCP = false;
        networking.firewall.enable = false;
        environment.systemPackages = with pkgs; [
          tftp-hpa
          jq
          dhcpcd
        ];
      };

      # UEFI PXE: OVMF firmware, romfile="" disables iPXE so OVMF uses
      # its native PXE stack and sends DHCP option 93 (client arch).
      pxeClientUEFI = { lib, ... }: {
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
        {
          pkgs,
          lib,
          ...
        }:
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
        HTTP_PORT = ${toString testHttpPort}
        # Single nginx vhost now serves both boot files and ISO files
        # (previously two separate darkhttpd units/ports).
        HTTP_BOOT_UNIT = "nginx.service"    # port HTTP_PORT, /
        HTTP_ISO_UNIT = "nginx.service"    # port HTTP_PORT, /isos/

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

        with subtest("TFTP service is ordered after the file-staging service"):
            # Regression: atftpd previously had no ordering dependency on
            # pxe-boot-main-script.service (the unit that rsyncs
            # grub.pxe/bootx64.efi/etc. into the tree atftpd serves from)
            # -- same race-condition class already fixed for
            # pxe-boot-prepare.service/nginx.service.
            after_units = router.succeed(
                f"systemctl show -p After --value {TFTP_UNIT}"
            )
            assert "pxe-boot-main-script.service" in after_units, (
                f"{TFTP_UNIT} is not ordered after pxe-boot-main-script.service: {after_units!r}"
            )

        with subtest("pxe-boot-prepare.service hardening regression guard"):
            # Pins both halves of the hardening knobs' history, so a
            # future edit accidentally reverting either direction is
            # caught here instead of silently reintroducing a known-bad
            # state:
            #   - ProtectKernelModules MUST stay "no" -- "yes" was tried
            #     and rolled back (see config-tftp.nix comment): it
            #     forces a private mount namespace, so this service's own
            #     mount() calls become invisible to nginx/other processes.
            #   - NoNewPrivileges MUST stay "yes" -- confirmed safe and
            #     should not regress back to unset/"no" as unrelated
            #     hardening work touches this unit.
            props = router.succeed(
                "systemctl show -p ProtectKernelModules -p NoNewPrivileges "
                "pxe-boot-prepare.service"
            )
            assert "ProtectKernelModules=no" in props, (
                f"ProtectKernelModules regressed away from 'no': {props!r}"
            )
            assert "NoNewPrivileges=yes" in props, (
                f"NoNewPrivileges regressed away from 'yes': {props!r}"
            )

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

        with subtest("tftpServer = false still stages grub/iPXE files"):
            for name in ["grubx64.efi", "grub.pxe", "grubaa64.efi", "main.ipxe"]:
                size = int(router.succeed(f"stat -c %s /srv/pxeboot/201/{name}").strip())
                assert size > 0, f"{name} is empty (0 bytes)"
            router.fail("systemctl is-active pxe-boot-tftp-server-for-interface-eth2.service")

        with subtest("tftpServer = true works standalone, without pxe-boot"):
            router.succeed("systemctl is-active pxe-boot-tftp-server-for-interface-eth3.service")
            router.succeed("test -d /srv/pxeboot/202")
            router.succeed("echo -n 'standalone-tftp-ok' > /srv/pxeboot/202/hello.txt")
            fetched = router.succeed(
                "tftp 192.168.77.1 -c get hello.txt /tmp/hello-fetched.txt && cat /tmp/hello-fetched.txt"
            )
            assert fetched == "standalone-tftp-ok", f"Unexpected TFTP payload: {fetched!r}"

        with subtest("disableTftpServerWarning still stages grub/iPXE files"):
            for name in ["grubx64.efi", "grub.pxe", "grubaa64.efi", "main.ipxe"]:
                size = int(router.succeed(f"stat -c %s /srv/pxeboot/203/{name}").strip())
                assert size > 0, f"{name} is empty (0 bytes)"
            router.fail("systemctl is-active pxe-boot-tftp-server-for-interface-eth4.service")

        with subtest("tftpServerRoot override: Rust-written grub.cfg and Nix-staged files agree"):
            for name in ["grubx64.efi", "grub.pxe", "grubaa64.efi", "main.ipxe"]:
                size = int(router.succeed(f"stat -c %s /srv/custom-tftp-root/204/{name}").strip())
                assert size > 0, f"{name} is empty (0 bytes)"
            eth5_grub_cfg_size = int(
                router.succeed("stat -c %s /srv/custom-tftp-root/204/grub/grub.cfg").strip()
            )
            assert eth5_grub_cfg_size > 0, "grub.cfg is empty (0 bytes)"
            router.fail("test -e /srv/pxeboot/204")

            router.succeed(
                "tftp 192.168.79.1 -c get grub.pxe /tmp/eth5-grub.pxe && "
                "test -s /tmp/eth5-grub.pxe"
            )
            router.succeed(
                "tftp 192.168.79.1 -c get grub/grub.cfg /tmp/eth5-grub.cfg && "
                "test -s /tmp/eth5-grub.cfg"
            )

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

        with subtest("nginx per-interface binding: standalone-tftp-only eth3 is isolated"):
            # eth3 is a standalone-TFTP fixture with pxe-boot disabled, so it
            # must NOT be in `pxeBootInterfaces` -- regression check for the
            # nginx `listen` binding (config-tftp.nix) actually staying
            # per-interface rather than silently falling back to `0.0.0.0`,
            # which would make this vhost reachable from every interface
            # including ones that never opted into PXE boot.
            ss_output = router.succeed(f"ss -tlnp 'sport = :{HTTP_PORT}'")
            # Column 4 is "Local Address:Port" -- column 5 ("Peer
            # Address:Port") is ALWAYS "0.0.0.0:*" for a listening TCP
            # socket regardless of how it's bound, so checking the whole
            # line's text for "0.0.0.0"/"*:" would false-positive on
            # every correctly-per-interface-bound listener too.
            local_addrs = [
                line.split()[3]
                for line in ss_output.splitlines()
                if line.startswith("LISTEN")
            ]
            assert local_addrs, f"no LISTEN sockets found on port {HTTP_PORT}: {ss_output!r}"
            for addr in local_addrs:
                assert not addr.startswith("192.168.77.1:"), (
                    "nginx is listening on eth3's address (192.168.77.1), which "
                    f"has pxe-boot disabled (standalone tftp only): {ss_output!r}"
                )
                assert not addr.startswith("0.0.0.0:") and not addr.startswith("*:"), (
                    f"nginx is listening on a wildcard address, not per-interface: {addr!r} in {ss_output!r}"
                )
            assert any(addr.startswith("${routerIp}:") for addr in local_addrs), (
                f"nginx is not listening on eth1's address (${routerIp}): {ss_output!r}"
            )
            router.fail(
                f"curl -s -f --connect-timeout 2 -m 5 --interface eth3 "
                f"http://192.168.77.1:{HTTP_PORT}/ > /dev/null"
            )

        with subtest("mount.rs: wrong ISO mounted at mountpoint triggers remount"):
            # Force a wrong-ISO-mounted state: unmount the correct ISO,
            # loop-mount a DIFFERENT, unrelated (small -- /tmp has nowhere
            # near enough room for a second copy of the real ~1.5GB ISO)
            # valid iso9660 image in its place. `verify_mount` compares
            # canonicalized backing-file PATHS (via
            # /sys/block/loopN/loop/backing_file), not content -- any
            # different path is "wrong", regardless of size/content, so
            # this still exercises the comparison itself correctly.
            mount_point = "/run/pxe-boot/iso-mountpoint/${testIsoName}"
            router.succeed(f"umount {mount_point}")
            router.succeed(
                "cp /run/pxe-boot/isos/rhel-9.6-x86_64-dvd.iso /tmp/decoy.iso && "
                f"mount -t iso9660 -o loop,ro /tmp/decoy.iso {mount_point}"
            )
            decoy_backing = router.succeed(
                "losetup -j /tmp/decoy.iso | cut -d: -f1"
            ).strip()
            assert decoy_backing, "decoy ISO was not actually loop-mounted"

            router.succeed("systemctl restart pxe-boot-prepare.service")
            status = router.succeed(
                "systemctl show -p ActiveState -p Result pxe-boot-prepare.service"
            )
            assert "Result=success" in status, f"pxe-boot-prepare restart failed: {status}"

            # The decoy's own loop device detaching is a kernel-internal
            # cleanup timing detail (autoclear-on-last-close), not
            # something our own code controls or needs to assert on --
            # force-detach it explicitly instead of waiting/hoping.
            router.succeed(f"losetup -d {decoy_backing} || true")

            # And the mountpoint must now carry the REAL ISO's backing
            # file again, not the decoy's.
            real_loop_dev = router.succeed(
                f"findmnt -n -o SOURCE {mount_point}"
            ).strip()
            backing_file = router.succeed(
                f"cat /sys/class/block/$(basename {real_loop_dev})/loop/backing_file"
            ).strip()
            assert "decoy" not in backing_file, (
                f"mountpoint still backed by the decoy file: {backing_file}"
            )
            assert "/run/pxe-boot/isos/${testIsoName}" in backing_file or backing_file.endswith(
                "${testIsoName}"
            ), f"mountpoint not backed by the real ISO: {backing_file}"

            # The reservation must be present and outside the pool.
            resv_ips = [r.get("ip-address") for r in subnet.get("reservations", [])]
            assert "${reservedPxeIp}" in resv_ips, \
                f"reserved IP ${reservedPxeIp} missing from subnet reservations: {resv_ips}"
            pool_str = subnet["pools"][0]["pool"]  # e.g. "192.168.75.10 - 192.168.75.254"
            pool_first = int(pool_str.split("-")[0].strip().split(".")[-1])
            assert int("${reservedPxeIp}".split(".")[-1]) < pool_first, \
                f"fixture broken: ${reservedPxeIp} should be below pool start {pool_str}"

            # The fix: require-client-classes for PXE must exist at the SUBNET level
            # so it applies to reserved clients too. (Pool-level alone is the bug.)
            subnet_req = subnet.get("require-client-classes", [])
            pxe_markers = ["UEFI (x86_64)", "BIOS Legacy", "iPXE"]
            have = [m for m in pxe_markers if any(m in c for c in subnet_req)]
            assert have, (
                "PXE boot classes are NOT required at the subnet level "
                f"(subnet require-client-classes={subnet_req}); reserved-IP clients "
                "will get no boot-file-name -> UEFI PXE-E16. Move "
                "`require-client-classes` from the pool to the subnet in "
                "nixosModule/config.nix."
            )
            router.log(f"  subnet-level PXE classes required: {subnet_req}")

            # match-client-id must be false on the PXE subnet so reservations are
            # keyed on MAC only. UEFI firmware / installer / installed OS use
            # different DUID-derived client-ids for the same MAC; with the kea
            # default (true) a stale firmware lease blocks the installed OS from
            # its reserved IP.
            assert subnet.get("match-client-id") is False, (
                "PXE subnet match-client-id must be false so a reserved IP is keyed "
                "on MAC only (else a stale firmware-phase DUID lease blocks the "
                f"installed OS). Got: {subnet.get('match-client-id')!r}"
            )
            router.log("  subnet match-client-id = false (MAC-only reservations)")

        with subtest("Autoinstall scripts are deployed"):
            # Ubuntu (cloud-init NoCloud) serves each script from its own seed
            # *directory* as `user-data` + `meta-data`, not as a flat file named
            # after the script (see AutoinstallManager::prepare) -- the GRUB
            # entry's `ds=nocloud-net;s=<dir>/` param points cloud-init at that
            # directory.
            ubuntu_ks = router.succeed(
                "cat /run/pxe-boot/unattented-install/ubuntu-24.04-live-server-amd64.iso/minimal.ks/user-data"
            )
            assert "lang en_US.UTF-8" in ubuntu_ks, f"Unexpected content: {ubuntu_ks[:200]}"
            assert "keyboard us" in ubuntu_ks, f"Missing 'keyboard us': {ubuntu_ks[:200]}"
            router.succeed(
                "test -f /run/pxe-boot/unattented-install/ubuntu-24.04-live-server-amd64.iso/minimal.ks/meta-data"
            )

            advanced_ks = router.succeed(
                "cat /run/pxe-boot/unattented-install/ubuntu-24.04-live-server-amd64.iso/advanced.ks/user-data"
            )
            assert "network --bootproto=dhcp" in advanced_ks, f"Unexpected: {advanced_ks[:200]}"
            router.succeed(
                "test -f /run/pxe-boot/unattented-install/ubuntu-24.04-live-server-amd64.iso/advanced.ks/meta-data"
            )

            # RHEL kickstart has no NoCloud datasource -- served verbatim as a
            # flat file under its own name.
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
                (HTTP_BOOT_UNIT, "nginx (boot files + ISO files, port 1337)"),
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
  };

  # Pure-eval check (no VM): `pxe-boot.disableTftpServerWarning` silences
  # the `tftpServer = false` reminder for the interface it's set on, without
  # affecting any other opted-out interface.
  tftpWarningsCheck =
    let
      evaluated = pkgs.nixos {
        imports = [ nixosModule.nixosModules.default ];
        my.router = {
          enable = true;
          pxe-boot = {
            enable = true;
            isoFolderPath = "/tmp/dummy-iso-dir";
          };
          configInterface = {
            eth1 = {
              mac = null;
              dhcp.server = {
                id = 900;
                address = "192.168.90.1/24";
                tftpServer = false;
                pxe-boot.enable = true;
              };
            };
            eth2 = {
              mac = null;
              dhcp.server = {
                id = 901;
                address = "192.168.91.1/24";
                tftpServer = false;
                pxe-boot = {
                  enable = true;
                  disableTftpServerWarning = true;
                };
              };
            };
          };
        };
      };
      warningsText = pkgs.lib.concatStringsSep "\n" evaluated.config.warnings;
      hasEth1Warning = pkgs.lib.hasInfix "\"eth1\"" warningsText;
      hasEth2Warning = pkgs.lib.hasInfix "\"eth2\"" warningsText;
    in
    pkgs.runCommand "pxe-boot-tftp-warnings-check" { } (
      if hasEth1Warning && !hasEth2Warning then
        "touch $out"
      else
        throw ''
          expected a warning for eth1 (tftpServer = false) and none for eth2
          (disableTftpServerWarning = true); got warnings:
          ${warningsText}
        ''
    );
}
