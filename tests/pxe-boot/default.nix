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
#   |  | eth1:    |  | eth1   |  | PXE iface,   |  | PXE iface,   |  |
#   |  |192.168.  |  |        |  | name varies  |  | name varies  |  |
#   |  |  75.1/24 |  |        |  | by kernel/   |  | by kernel/   |  |
#   |  |          |  |        |  | bus, DHCP    |  | bus, DHCP    |  |
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
  # Byte-identical copy of the same NixOS ISO, served from a SEPARATE
  # DHCP interface/client dedicated to the findiso-download failure-path
  # subtest -- breaking its raw-download entry (see that subtest) must
  # not affect the real BIOS/UEFI clients sharing testIsoName above.
  findisoFailureIsoName = "nixos-pxe-findiso-failure-test.iso";
  pxeMacFindisoFailure = "52:54:00:aa:01:04";

  # NOT 52:54:00:12:xx:xx -- that exact prefix is what nixpkgs' OWN
  # nixosTest framework auto-assigns to the SEPARATE management/vlan NIC it
  # adds for every `virtualisation.vlans` entry (`qemuNicMac` in
  # nixos/lib/qemu-common.nix: `52:54:00:12:${net}:${nodeNumber}`,
  # nodeNumber = 1-based position in alphabetically-sorted node names).
  # pxeClientBIOS happens to be nodeNumber 2 on vlan 1, so the old
  # "52:54:00:12:01:02" collided EXACTLY with that auto-assigned NIC's own
  # MAC -- two real QEMU network devices (ours, explicitly added via
  # qemu.networkingOptions, and the framework's own vlan-1 one) sharing one
  # MAC confused NetworkManager/DHCP enough to delay IPv4 address
  # acquisition past any reasonable beacon-script timeout.
  pxeMacBIOS = "52:54:00:aa:01:02";
  pxeMacUEFI = "52:54:00:aa:01:03";
  # Regression: a reservation with an IP OUTSIDE the DHCP pool (.10-.254).
  # Reserved-IP clients do not draw from the pool, so PXE boot classes that are
  # only required at the POOL level never fire for them -> their DHCP offer
  # carries no next-server/boot-file-name -> UEFI/OVMF fails with
  # "PXE-E16: No valid offer received". The pxe classes must therefore be
  # required at the SUBNET level. See the "reserved-IP client" subtest below.
  reservedPxeMac = "52:54:00:12:01:09";
  reservedPxeIp = "192.168.75.5"; # < firstIP (.10) => outside the pool

  # D35: a reservation purely to exercise the per-MAC default-entry
  # override's Nix-to-JSON-to-Rust wiring -- no VM uses this MAC.
  d35OverrideMac = "52:54:00:aa:01:05";
  d35OverrideIp = "192.168.75.6";

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

            # gawk: NOT optional -- beacon.sh's interface/IP discovery is
            # awk-based; without it on PATH, every awk invocation fails
            # silently ("command not found" under `|| true`).
            path = with pkgs; [
              curl
              iproute2
              networkmanager
              systemd
              gawk
              coreutils
            ];
            script = builtins.readFile ./beacon.sh;
          };

          # modules/iso-builder's own "Wired-Auto" NetworkManager profile
          # (reused as-is: it's a plain assignment, so mkForce cleanly wins
          # here, unlike fileSystems above) uses `ipv6.method=auto,
          # may-fail=true` -- reasonable for real-world use where IPv6 may
          # genuinely be present, but this test's VLAN is isolated with no
          # IPv6 router at all. `may-fail=true` only means SLAAC failure
          # doesn't fail the WHOLE connection -- NetworkManager still waits
          # out its own internal SLAAC retry/timeout window before
          # considering activation complete and flushing the (already-
          # obtained) IPv4 lease to the kernel: `nmcli` reports the device
          # "connected" well under 90s, but `ip addr show` doesn't show the
          # IPv4 address until ~90s+ later -- exactly NetworkManager's own
          # default activation-timeout window. `method=disabled` skips
          # SLAAC entirely, removing that wait at
          # the root instead of just padding the beacon script's own
          # polling window to outlast it.
          environment.etc."NetworkManager/system-connections/Wired-Auto.nmconnection" = lib.mkForce {
            text = ''
              [connection]
              id=Wired-Auto
              type=ethernet
              autoconnect=true
              autoconnect-priority=999

              [ethernet]

              [ipv4]
              method=auto
              may-fail=false

              [ipv6]
              method=disabled

              [proxy]
            '';
            mode = "0600";
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
    cp ${testNixosIso}/iso/*.iso $out/${findisoFailureIsoName}

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
  # nixIsos fixture: mimics the SHAPE of a real modules/iso-builder package
  # (`$out/iso/<name>`, name == isoImage.isoName) without actually building
  # a full bootable NixOS ISO -- B8: this option previously had zero test
  # coverage, neither pure-eval (Nix-side wiring: tmpfiles symlink farm,
  # PathChanged, duplicate-name assertion) nor E2E (is a nixIsos-sourced
  # ISO actually discovered/served the same as an isoFolderPath one).
  ###########################################################################
  nixIsoName = "nix-sourced-test.iso";
  nixIsoPackage = pkgs.runCommand nixIsoName { nativeBuildInputs = [ pkgs.xorriso ]; } ''
    mkdir -p $out/iso
    mkdir -p rhel-root/images/pxeboot
    echo "Red Hat GPG Key" > rhel-root/RPM-GPG-KEY-redhat-release
    echo "Mock RHEL kernel (nix-sourced)" > rhel-root/images/pxeboot/vmlinuz
    echo "Mock RHEL initrd (nix-sourced)" > rhel-root/images/pxeboot/initrd.img
    xorriso -as mkisofs \
      -o "$out/iso/${nixIsoName}" \
      -V "RHEL-9-6-0-NixSourced-x86_64" \
      -r -J \
      rhel-root/
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
      # These are diskless findiso= clients: the whole downloaded ISO
      # (currently >1.4GB) lands in /run (tmpfs, then losetup'd), inside
      # the initrd stage. The download was silently stalling partway
      # through and never finishing within the beacon subtest's 1200s
      # budget; the stall point scaled linearly with `memorySize` across
      # three measurements (2048/4096/6144MB -> ~19% of memorySize each
      # time, not proportional to elapsed time), so it's RAM-bound, not
      # a protocol timeout. Explicitly setting `boot.runSize` (below)
      # didn't change the ratio, so the limit isn't /run's own tmpfs
      # quota specifically -- more likely the initrd's own root ramfs,
      # which scales with total VM memory the same way. Sized via
      # linear extrapolation from those three measurements for a ~30%
      # margin over the current ISO size.
      memorySize = 10240;
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

    # See the memorySize comment above: must comfortably exceed the
    # downloaded ISO's size, independent of total VM RAM.
    boot.runSize = "3G";

    fileSystems."/" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [
        "mode=0755"
        "size=3G"
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
          6
        ];
        networking.useDHCP = false;

        # Lets the router itself fetch from its own standalone TFTP server
        # (eth3, below) to verify it actually serves files end-to-end.
        environment.systemPackages = [ pkgs.tftp-hpa ];

        my.router = {
          enable = true;

          pxe-boot = {
            enable = true;
            isoFolderPath = dummyIsoDir;
            # B8: proves nixIsos is discovered/served exactly like an
            # isoFolderPath-discovered ISO (see the "GRUB config includes
            # all detected ISOs" subtest below).
            nixIsos = [ nixIsoPackage ];
            # Real routers typically have enough cores that nginx's
            # bulk-ISO-transfer path never actually starves other
            # clients' latency-sensitive requests (see
            # isoDownloadRateLimit's option doc) -- but THIS test's
            # router VM runs on a single vCPU, which reproduces exactly
            # that contention against GRUB's legacy BIOS/SeaBIOS PXE
            # driver (no transmit retry logic) unless capped.
            isoDownloadRateLimit = "20m";
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
                    # D35: per-MAC default-entry override -- this
                    # reservation never PXE-boots a real VM in this test
                    # (that would require a 4th bootable ISO fixture just
                    # to prove index selection); it only has to exist so
                    # generate_grub_menu writes its override file, which
                    # the "D35" subtest below reads directly off the
                    # router. The GRUB-side consumption of that file
                    # (${"$"}{net_default_mac} + configfile) was verified
                    # separately via a live E2E probe.
                    "${d35OverrideMac}" = {
                      ip-address = d35OverrideIp;
                      defaultIso = "rhel-9.6-x86_64-dvd.iso";
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

            # findiso-download failure-path fixture: a dedicated
            # interface/client whose default ISO is a byte-identical
            # copy of testIsoName under a different filename (see the
            # "findiso-download failure path" subtest below, which
            # breaks only THIS filename's raw-download entry, never
            # testIsoName's -- the real BIOS/UEFI clients on eth1 must
            # keep working).
            eth6 = {
              mac = null;
              dhcp = {
                server = {
                  id = 205;
                  address = "192.168.80.1/24";
                  firstIP = 10;
                  pxe-boot = {
                    enable = true;
                    defaultIso = findisoFailureIsoName;
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

      # findiso-download failure-path fixture (see eth6 above): UEFI PXE
      # client on its own dedicated vlan, same base as pxeClientUEFI.
      pxeClientFindisoFailure = { lib, ... }: {
        imports = [ pxeboot_vm_base ];
        virtualisation = {
          vlans = lib.mkForce [ 6 ];
          useEFIBoot = true;
          qemu.networkingOptions = lib.mkForce [
            "-netdev vde,id=pxefindisofail1,sock=\"$QEMU_VDE_SOCKET_6\""
            "-device virtio-net-pci,netdev=pxefindisofail1,mac=${pxeMacFindisoFailure},romfile=,bootindex=1"
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

        with subtest("nixIsos: Nix-store-sourced ISO is discovered and served (B8)"):
            # GRUB entry titles are built from the ISO's FILENAME
            # (see grub/entry.rs), not its internal volume label -- check
            # for the actual filename, distinguishable from the OTHER
            # (isoFolderPath-discovered) RHEL ISO's own filename
            # ("rhel-9.6-x86_64-dvd.iso") by design, so this specifically
            # proves the nixIsos symlink-farm path, not just that SOME
            # RHEL-shaped ISO was found.
            assert "${nixIsoName}" in grub_cfg, \
                f"GRUB config missing the nixIsos-sourced ISO's entry ('${nixIsoName}'): {grub_cfg}"
            router.succeed("test -e /run/pxe-boot/isos/${nixIsoName}")
            router.succeed(
                "readlink -f /run/pxe-boot/isos/${nixIsoName} | grep -q '^/nix/store/'"
            )
            router.succeed(f"curl -s -f http://${routerIp}:{HTTP_PORT}/isos/${nixIsoName} > /dev/null")

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

        with subtest("D35: per-MAC override grub.cfg has the same menu but a different default"):
            override_cfg = router.succeed(
                "cat /srv/pxeboot/200/grub/grub.cfg-override-${d35OverrideMac}"
            )
            override_entries = re.findall(r'menuentry\s+"([^"]+)"', override_cfg)
            assert override_entries == menu_entries, \
                f"Override menu must list the exact same entries as the base grub.cfg: {override_entries} vs {menu_entries}"

            override_default_match = re.search(r'set default=(\d+)', override_cfg)
            assert override_default_match, "No 'set default=' in override GRUB config"
            override_default_idx = int(override_default_match.group(1))
            assert "rhel" in override_entries[override_default_idx].lower(), \
                f"Override default entry is '{override_entries[override_default_idx]}', expected the reservation's RHEL override"
            assert override_default_idx != default_idx, \
                "Override default must differ from the interface-level default -- otherwise this test can't tell the override apart from a no-op"

        with subtest("NixOS ISO is mounted and served via HTTP"):
            router.succeed("test -d /run/pxe-boot/iso-mountpoint/${testIsoName}")
            boot_contents = router.succeed("ls /run/pxe-boot/iso-mountpoint/${testIsoName}/boot/")
            assert "nix" in boot_contents or "bzImage" in boot_contents, \
                f"Unexpected ISO boot dir contents: {boot_contents}"
            router.succeed(f"curl -s -f http://${routerIp}:{HTTP_PORT}/isos/${testIsoName} > /dev/null")

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

        with subtest("Break findiso-download's raw-ISO entry for the dedicated failure-test client"):
            # Dedicated copy (eth6/pxeClientFindisoFailure) -- removing
            # this symlink must NOT touch testIsoName's own entry, which
            # the real BIOS/UEFI clients on eth1 still depend on.
            router.succeed("test -e /run/pxe-boot/isos/${findisoFailureIsoName}")
            router.succeed("rm /run/pxe-boot/isos/${findisoFailureIsoName}")
            router.succeed("test -e /run/pxe-boot/isos/${testIsoName}")
            pxeClientFindisoFailure.start(allow_reboot=False)

        # Kea client-classes / PXE-E16 subnet-level require-client-classes /
        # match-client-id correctness is checked by the pure-eval
        # `pxe-boot-kea-client-classes` check instead (B19): purely a
        # function of module evaluation, it never needed a booted VM.
        # The reservation fixture (reservedPxeMac/reservedPxeIp above)
        # stays here to prove kea-dhcp4-server.service itself starts
        # cleanly with an outside-the-pool reservation present -- a real
        # service-level fact the pure-eval check can't verify.

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

            with subtest("findiso-download failure path: client reaches emergency mode"):
                # The raw-ISO entry for this client's dedicated ISO was
                # deliberately removed earlier (404 on fetch) -- GRUB
                # still fetches kernel/initrd fine (served from
                # /iso-mountpoint/, untouched), boots into the initrd,
                # wget fails on the missing /isos/ file, and
                # findiso-download.service's `OnFailure=emergency.target`
                # (see modules/iso-builder) must catch it instead of
                # hanging forever.
                pxeClientFindisoFailure.wait_for_console_text(
                    r"(?i)emergency mode", timeout=300
                )
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
            for vm in [pxeClientBIOS, pxeClientUEFI, pxeClientFindisoFailure]:
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

  # Pure-eval check (no VM): Kea's rendered DHCP config has the PXE
  # client-classes wired, and (PXE-E16 regression) `require-client-classes`
  # / `match-client-id` land at the SUBNET level, not just the pool --
  # moved out of the real VM E2E test (B19): this is purely a function of
  # module evaluation (`environment.etc."kea/dhcp4-server.conf".text`),
  # it never needed a booted router VM to check at all.
  keaPxeClientClassesCheck =
    let
      reservedPxeMac = "52:54:00:12:01:f0";
      reservedPxeIp = "192.168.92.5";
      evaluated = pkgs.nixos {
        imports = [ nixosModule.nixosModules.default ];
        my.router = {
          enable = true;
          pxe-boot = {
            enable = true;
            isoFolderPath = "/tmp/dummy-iso-dir";
          };
          configInterface.eth1 = {
            mac = null;
            dhcp.server = {
              id = 920;
              address = "192.168.92.1/24";
              firstIP = 10;
              reservations."${reservedPxeMac}".ip-address = reservedPxeIp;
              pxe-boot.enable = true;
            };
          };
        };
      };
      # nixpkgs' services.kea module renders this via a build step (likely
      # so it can config-check the JSON with kea's own binary), not plain
      # `builtins.toJSON` -- `.text` is null, `.source` is a derivation
      # that must actually be realized (import-from-derivation) to read.
      # Still far cheaper than the real VM test: one small derivation
      # build, not booting multiple QEMU machines.
      kea = builtins.readFile evaluated.config.environment.etc."kea/dhcp4-server.conf".source;
      # `fromJSON` rejects strings carrying Nix string context (which
      # `readFile` on a derivation output always attaches) -- safe to
      # discard here: these values are only ever compared/inspected
      # inside this check, never spliced into something that needs to
      # re-establish the build dependency on kea-dhcp4.conf.
      keaJson = builtins.fromJSON (builtins.unsafeDiscardStringContext kea);
      classNames = map (c: c.name) keaJson.Dhcp4.client-classes;
      hasClassContaining = keyword: builtins.any (n: pkgs.lib.hasInfix keyword n) classNames;
      hasUefiX86Class = builtins.any (
        n: pkgs.lib.hasInfix "UEFI" n && pkgs.lib.hasInfix "x86_64" n
      ) classNames;

      subnet = pkgs.lib.findFirst (s: s.id == 920) null keaJson.Dhcp4.subnet4;
      resvIps = map (r: r."ip-address") (subnet.reservations or [ ]);
      subnetReq = subnet."require-client-classes" or [ ];
      pxeMarkers = [
        "UEFI (x86_64)"
        "BIOS Legacy"
        "iPXE"
      ];
      hasSubnetPxeClasses = builtins.any (
        m: builtins.any (c: pkgs.lib.hasInfix m c) subnetReq
      ) pxeMarkers;
      matchClientIdFalse = (subnet."match-client-id" or null) == false;

      checks = [
        {
          name = "client-classes contains iPXE/BIOS/aarch64 markers";
          ok = hasClassContaining "iPXE" && hasClassContaining "BIOS" && hasClassContaining "aarch64";
        }
        {
          name = "client-classes contains a UEFI x86_64 class";
          ok = hasUefiX86Class;
        }
        {
          name = "reservation present and outside the pool";
          ok = subnet != null && builtins.elem reservedPxeIp resvIps;
        }
        {
          name = "PXE classes required at the SUBNET level (PXE-E16 regression)";
          ok = subnet != null && hasSubnetPxeClasses;
        }
        {
          name = "match-client-id is false on the PXE subnet";
          ok = subnet != null && matchClientIdFalse;
        }
      ];
      failures = builtins.filter (c: !c.ok) checks;
    in
    pkgs.runCommand "pxe-boot-kea-client-classes-check" { } (
      if failures == [ ] then
        "touch $out"
      else
        throw ''
          Kea DHCP config check(s) failed: ${builtins.toJSON (map (f: f.name) failures)}

          client-classes: ${builtins.toJSON classNames}
          subnet: ${builtins.toJSON subnet}
        ''
    );

  # Pure-eval check (no VM): `nixIsos`'s Nix-side wiring (B8) -- the
  # real symlink-farm/discovery/GRUB-entry behavior is covered by the
  # "nixIsos: Nix-store-sourced ISO is discovered and served" subtest in
  # the VM test above; this covers the parts that are purely a function
  # of module evaluation and never needed a booted VM:
  #   - the `systemd.tmpfiles.rules "L+"` entry exists when nixIsos is
  #     non-empty
  #   - `PathChanged` on the auto-refresh path unit includes nixIsosDir
  #   - the duplicate-`.name` assertion actually fires
  nixIsosWiringCheck =
    let
      mkNixIsoFixture =
        name: extra:
        pkgs.runCommand name ({ passthru.isNixIsoFixture = true; } // extra) ''
          mkdir -p "$out/iso"
          touch "$out/iso/${name}"
        '';
      pkgA = mkNixIsoFixture "nixisos-fixture-a.iso" { };
      pkgB = mkNixIsoFixture "nixisos-fixture-b.iso" { };
      # Same `.name` as pkgA, but a DIFFERENT derivation (distinguished
      # via an otherwise-inert env var) -- the dedup check in
      # config-tftp.nix is keyed on `.name`, not derivation identity, so
      # two textually-identical `runCommand` calls would just collapse
      # to the same store path and never exercise the collision at all.
      pkgDup = mkNixIsoFixture "nixisos-fixture-a.iso" { DISAMBIGUATE = "dup"; };

      mkEvaluated =
        nixIsos:
        pkgs.nixos {
          imports = [ nixosModule.nixosModules.default ];
          my.router = {
            enable = true;
            pxe-boot = {
              enable = true;
              isoFolderPath = "/tmp/dummy-iso-dir";
              inherit nixIsos;
            };
            configInterface.eth1 = {
              mac = null;
              dhcp.server = {
                id = 930;
                address = "192.168.93.1/24";
                pxe-boot.enable = true;
              };
            };
          };
        };

      evaluatedGood = mkEvaluated [
        pkgA
        pkgB
      ];
      nixIsosDir = evaluatedGood.config.my.router.pxe-boot.nixIsosDir;
      tmpfilesRules = evaluatedGood.config.systemd.tmpfiles.rules;
      hasLPlusRule = builtins.any (r: pkgs.lib.hasPrefix "L+ ${nixIsosDir} " r) tmpfilesRules;
      pathChanged =
        evaluatedGood.config.systemd.paths.pxe-boot-prepare-auto-refresh.pathConfig.PathChanged;
      hasPathChangedEntry = builtins.elem nixIsosDir pathChanged;

      evaluatedBad = mkEvaluated [
        pkgA
        pkgDup
      ];
      hasDuplicateAssertion = builtins.any (
        a: !a.assertion && pkgs.lib.hasInfix "nixIsos" a.message
      ) evaluatedBad.config.assertions;

      checks = [
        {
          name = "systemd.tmpfiles.rules has an L+ entry for nixIsosDir";
          ok = hasLPlusRule;
        }
        {
          name = "auto-refresh path unit's PathChanged includes nixIsosDir";
          ok = hasPathChangedEntry;
        }
        {
          name = "duplicate nixIsos package name triggers an assertion";
          ok = hasDuplicateAssertion;
        }
      ];
      failures = builtins.filter (c: !c.ok) checks;
    in
    pkgs.runCommand "pxe-boot-nix-isos-wiring-check" { } (
      if failures == [ ] then
        "touch $out"
      else
        throw ''
          nixIsos wiring check(s) failed: ${builtins.toJSON (map (f: f.name) failures)}

          nixIsosDir: ${nixIsosDir}
          tmpfiles.rules: ${builtins.toJSON tmpfilesRules}
          PathChanged: ${builtins.toJSON pathChanged}
          nixIsos-related assertions found: ${builtins.toJSON hasDuplicateAssertion}
        ''
    );

  # Pure-eval check (no VM): `isoDownloadRateLimit` (B10) -- set, it must
  # reach nginx's `/isos/` location as a `limit_rate` directive; unset
  # (the default), that location must not emit a `limit_rate` at all
  # (confirming the `mkIf` guard actually omits it, not just that the
  # REAL E2E test's own fixture -- which always sets it -- happens to
  # work).
  isoDownloadRateLimitCheck =
    let
      mkEvaluated =
        isoDownloadRateLimit:
        pkgs.nixos {
          imports = [ nixosModule.nixosModules.default ];
          my.router = {
            enable = true;
            pxe-boot = {
              enable = true;
              isoFolderPath = "/tmp/dummy-iso-dir";
            }
            // pkgs.lib.optionalAttrs (isoDownloadRateLimit != null) {
              inherit isoDownloadRateLimit;
            };
            configInterface.eth1 = {
              mac = null;
              dhcp.server = {
                id = 940;
                address = "192.168.94.1/24";
                pxe-boot.enable = true;
              };
            };
          };
        };

      isosLocationConfig =
        evaluated: evaluated.config.services.nginx.virtualHosts."pxe-boot".locations."/isos/" or null;

      withLimit = mkEvaluated "20m";
      withLimitExtraConfig = (isosLocationConfig withLimit).extraConfig or "";

      withoutLimit = mkEvaluated null;
      withoutLimitLocation = isosLocationConfig withoutLimit;
      withoutLimitExtraConfig = withoutLimitLocation.extraConfig or "";

      checks = [
        {
          name = "isoDownloadRateLimit = \"20m\" reaches nginx as limit_rate 20m;";
          ok = pkgs.lib.hasInfix "limit_rate 20m;" withLimitExtraConfig;
        }
        {
          name = "isoDownloadRateLimit = null (default) emits no limit_rate directive";
          ok = !(pkgs.lib.hasInfix "limit_rate" withoutLimitExtraConfig);
        }
      ];
      failures = builtins.filter (c: !c.ok) checks;
    in
    pkgs.runCommand "pxe-boot-iso-download-rate-limit-check" { } (
      if failures == [ ] then
        "touch $out"
      else
        throw ''
          isoDownloadRateLimit check(s) failed: ${builtins.toJSON (map (f: f.name) failures)}

          with "20m" extraConfig: ${builtins.toJSON withLimitExtraConfig}
          without limit extraConfig: ${builtins.toJSON withoutLimitExtraConfig}
        ''
    );

  # Pure-eval check (no VM): full-disable state (B18) -- with
  # `my.router.pxe-boot.enable = false` (the GLOBAL switch) and no
  # interface opted into standalone TFTP, every pxe-boot-related
  # service/vhost/tmpfiles-rule must be fully absent, not merely
  # dormant. Also proves the inverse established earlier in this file
  # (config-tftp.nix comment on `tftpServerInterfaces`): a standalone
  # `tftpServer = true` interface with `pxe-boot.enable` left at its
  # default (false) must still come up even while the GLOBAL
  # `pxe-boot.enable` switch is off.
  fullDisableCheck =
    let
      disabledEvaluated = pkgs.nixos {
        imports = [ nixosModule.nixosModules.default ];
        my.router = {
          enable = true;
          pxe-boot.enable = false;
          configInterface.eth1 = {
            mac = null;
            dhcp.server = {
              id = 950;
              address = "192.168.95.1/24";
            };
          };
        };
      };

      standaloneEvaluated = pkgs.nixos {
        imports = [ nixosModule.nixosModules.default ];
        my.router = {
          enable = true;
          pxe-boot.enable = false;
          configInterface.eth1 = {
            mac = null;
            dhcp.server = {
              id = 951;
              address = "192.168.96.1/24";
              tftpServer = true;
            };
          };
        };
      };

      checks = [
        {
          name = "pxe-boot-prepare.service absent when pxe-boot.enable = false";
          ok = !(disabledEvaluated.config.systemd.services ? "pxe-boot-prepare");
        }
        {
          name = "pxe-boot-main-script.service absent when pxe-boot.enable = false";
          ok = !(disabledEvaluated.config.systemd.services ? "pxe-boot-main-script");
        }
        {
          name = "nginx pxe-boot vhost absent when pxe-boot.enable = false";
          ok = !(disabledEvaluated.config.services.nginx.virtualHosts ? "pxe-boot");
        }
        {
          name = "no TFTP unit created for an interface with no tftpServer/pxe-boot at all";
          ok = !(disabledEvaluated.config.systemd.services ? "pxe-boot-tftp-server-for-interface-eth1");
        }
        {
          name = "standalone tftpServer=true interface still gets a TFTP unit despite pxe-boot.enable=false";
          ok = standaloneEvaluated.config.systemd.services ? "pxe-boot-tftp-server-for-interface-eth1";
        }
      ];
      failures = builtins.filter (c: !c.ok) checks;
    in
    pkgs.runCommand "pxe-boot-full-disable-check" { } (
      if failures == [ ] then
        "touch $out"
      else
        throw ''
          Full-disable check(s) failed: ${builtins.toJSON (map (f: f.name) failures)}

          disabled systemd.services: ${builtins.toJSON (builtins.attrNames disabledEvaluated.config.systemd.services)}
          standalone systemd.services: ${builtins.toJSON (builtins.attrNames standaloneEvaluated.config.systemd.services)}
        ''
    );
}
