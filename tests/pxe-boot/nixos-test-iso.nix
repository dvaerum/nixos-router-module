{
  pkgs,
  routerIp,
  httpPort,
  isoName,
  volumeID ? "NIXOS_PXE_TEST",
}:
###########################################################################
# Test ISO shared by the PXE VM tests: a NixOS image built by
# modules/iso-builder that sends a beacon HTTP request to the router once it
# has booted, proving the whole boot (see ./beacon.sh).
###########################################################################
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

      isoImage.isoName = lib.mkForce isoName;
      isoImage.volumeID = lib.mkForce volumeID;

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
          Environment = "ROUTER_IP=${routerIp} HTTP_PORT=${toString httpPort}";
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
nixosSystem.config.system.build.isoImage
