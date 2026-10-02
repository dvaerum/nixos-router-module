{
  pkgs,
  config,
  lib,
  netLib,
  ...
}:
let
  functions-general = import ./functions/general.nix {
    inherit
      pkgs
      lib
      config
      netLib
      ;
  };
  inherit (functions-general)
    cfgSetDnsServerInterfaceOnly
    qualifyingSuffixFor
    ;

  ipv4_fn = import ./functions/ipv4.nix { inherit lib netLib; };

  cfg = config.my.router;

  lanInterfaces = lib.filter (
    dhcp_interface_conf: dhcp_interface_conf.dhcp.server.dns-server.trust == "lan"
  ) cfgSetDnsServerInterfaceOnly;

  spoofOverridesEnabled = cfg.dns-server.spoof.overrides != { };
  spoofBlocklistEnabled = cfg.dns-server.spoof.blocklist.enable;
  spoofEnabled = spoofOverridesEnabled || spoofBlocklistEnabled;

  # Whether there's anywhere to publish DHCP-lease-derived records at all.
  leaseHookEnabled = lanInterfaces != [ ];

  # {mac, fqdn} pairs from every lan-trust, dns-server-enabled interface's
  # hostname-bearing reservations -- flattened across interfaces (MACs are
  # unique regardless of which subnet they're reserved on), FQDN-qualified
  # per that interface's own domain, matching what Kea itself reports via
  # LEASE4_HOSTNAME for the same reservation (see `ddns-qualifying-suffix`
  # in config.nix). `dns-server-lease-hook.sh` compares against the bare,
  # no-trailing-dot form, matching `rpzTriggerName` elsewhere in this file.
  hostnameReservations = lib.concatMap (
    dhcp_interface_conf:
    let
      suffix = qualifyingSuffixFor dhcp_interface_conf;
      qualify =
        hostname: if suffix == null then hostname else "${hostname}.${lib.strings.removeSuffix "." suffix}";
    in
    lib.mapAttrsToList
      (mac: value: {
        mac = lib.toLower mac;
        fqdn = qualify value.hostname;
      })
      (lib.filterAttrs (_mac: value: value.hostname != null) dhcp_interface_conf.dhcp.server.reservations)
  ) lanInterfaces;

  # Collision list for pool-lease hostnames (dns-server-lease-hook.sh):
  # anything a client-supplied hostname must never be allowed to claim.
  reservedFqdns =
    (map (r: r.fqdn) hostnameReservations) ++ builtins.attrNames cfg.dns-server.spoof.overrides;

  # RPZ QNAME triggers are, by protocol convention, records whose name is
  # the blocked/overridden domain *relative to the RPZ zone's own origin*
  # (unbound rejects anything else: "name of record ... is not a subdomain
  # of the configured name of the RPZ zone"). So the hostname must be
  # written WITHOUT a trailing dot, letting the zonefile parser append the
  # zone's own `name:` as `$ORIGIN` -- an absolute FQDN here is wrong, not
  # just unnecessary.
  rpzTriggerName = name: lib.strings.removeSuffix "." name;

  overridesRpzFile = pkgs.writeText "dns-server-spoof-overrides.rpz" ''
    $TTL 60
    @ SOA localhost. admin.localhost. (1 3600 900 604800 60)
    @ NS  localhost.
    ${lib.concatStringsSep "\n" (
      lib.concatLists (
        lib.mapAttrsToList (
          hostname: ips: lib.forEach ips (ip: "${rpzTriggerName hostname} A ${ip}")
        ) cfg.dns-server.spoof.overrides
      )
    )}
  '';

  blocklistStateDirectory = "dns-server-blocklist";
  blocklistRpzFile = "/var/lib/${blocklistStateDirectory}/blocklist.rpz";

  blocklistUpdateScript = pkgs.writeShellApplication {
    name = "dns-server-blocklist-update";
    runtimeInputs = with pkgs; [
      curl
      gawk
      gnugrep
      coreutils
      diffutils
      systemd
    ];
    text = builtins.readFile ./scripts/dns-server-blocklist-update.sh;
  };

  # Nested under Kea's own StateDirectory ("kea", i.e. /var/lib/kea) rather
  # than a new top-level state dir: kea-dhcp4-server's DynamicUser sandbox
  # only grants write access there, and adding a second StateDirectory
  # entry from a different module risks conflicting with kea.nix's own
  # definition of the same systemd option.
  #
  # This is where the hook SCRIPT writes and where the reload-trigger path
  # unit watches -- it is NOT what unbound reads. `DynamicUser = true`
  # (kea.nix) makes systemd create StateDirectory entries under
  # /var/lib/private/, "host directories made inaccessible to unprivileged
  # users" (systemd.exec(5)) -- that restriction is on /var/lib/private/
  # itself, so no chmod on our own subdirectory can get the (unprivileged,
  # non-root) unbound user past it. Root is unaffected, so
  # dns-server-leases-sync.sh (root, triggered off this path) copies the
  # file out to leasesSharedFile below, which unbound actually reads.
  leasesKeaStateDirectory = "/var/lib/kea/dns-server-leases";
  leasesKeaFile = "${leasesKeaStateDirectory}/leases.rpz";

  leasesSharedStateDirectory = "/var/lib/dns-server-leases";
  leasesSharedFile = "${leasesSharedStateDirectory}/leases.rpz";

  leasesSyncScript = pkgs.writeShellApplication {
    name = "dns-server-leases-sync";
    runtimeInputs = with pkgs; [
      coreutils
      systemd
    ];
    runtimeEnv = {
      DNS_SERVER_LEASES_KEA_FILE = leasesKeaFile;
      DNS_SERVER_LEASES_SHARED_FILE = leasesSharedFile;
    };
    text = builtins.readFile ./scripts/dns-server-leases-sync.sh;
  };

  allowedSubnetIdsFile = pkgs.writeText "dns-server-lease-hook-allowed-subnet-ids" (
    lib.concatMapStringsSep "\n" (
      dhcp_interface_conf: builtins.toString dhcp_interface_conf.dhcp.server.id
    ) lanInterfaces
  );

  reservedMacsFile = pkgs.writeText "dns-server-lease-hook-reserved-macs" (
    lib.concatMapStringsSep "\n" (r: r.mac) hostnameReservations
  );

  reservedFqdnsFile = pkgs.writeText "dns-server-lease-hook-reserved-fqdns" (
    lib.concatStringsSep "\n" reservedFqdns
  );

  leaseHookScript = pkgs.writeShellApplication {
    name = "dns-server-lease-hook";
    runtimeInputs = with pkgs; [
      gnugrep
      coreutils
      diffutils
      findutils
    ];
    runtimeEnv = {
      DNS_SERVER_LEASES_STATE_DIR = leasesKeaStateDirectory;
      DNS_SERVER_LEASES_RPZ_OUT = leasesKeaFile;
      DNS_SERVER_ALLOWED_SUBNET_IDS_FILE = "${allowedSubnetIdsFile}";
      DNS_SERVER_RESERVED_MACS_FILE = "${reservedMacsFile}";
      DNS_SERVER_RESERVED_FQDNS_FILE = "${reservedFqdnsFile}";
      DNS_SERVER_PUBLISH_POOL_LEASES = if cfg.dns-server.publish-leases.enable then "1" else "0";
    };
    text = builtins.readFile ./scripts/dns-server-lease-hook.sh;
  };

  rpzZones =
    lib.optional spoofOverridesEnabled {
      name = "dns-server-spoof-overrides.internal.";
      zonefile = "${overridesRpzFile}";
      tags = ''"lan"'';
    }
    ++ lib.optional spoofBlocklistEnabled {
      name = "dns-server-spoof-blocklist.internal.";
      zonefile = blocklistRpzFile;
      # `blocklistRpzFile` doesn't exist at build/checkconf time (it's
      # populated at runtime by `dns-server-blocklist-update.service`) --
      # with unbound 1.23, a `zonefile:` with no `primary`/`url` and a
      # missing file is a *fatal* checkconf error ("Could not setup
      # authority zones"), not the "will fetch it later" warning the docs
      # describe. Any `url` value avoids that path; port 1 on loopback
      # guarantees an instant connection-refused rather than a hanging
      # DNS/TCP timeout on the rare occasion unbound actually tries it
      # (e.g. a restart that races the update service's first run).
      url = "http://127.0.0.1:1/unused-placeholder.rpz";
      tags = ''"lan"'';
    }
    ++ lib.optional leaseHookEnabled {
      name = "dns-server-leases.internal.";
      zonefile = leasesSharedFile;
      # Same reasoning as the blocklist zone above: doesn't exist until
      # dns-server-leases-sync.sh's first run copies it into place.
      url = "http://127.0.0.1:1/unused-placeholder.rpz";
      tags = ''"lan"'';
    };
in
(lib.mkIf (lib.length cfgSetDnsServerInterfaceOnly > 0) {
  services.unbound = {
    enable = true;

    # `services.unbound.checkconf` silently defaults to `false` once any
    # `remote-control` setting exists in `settings` (which
    # `localControlSocketPath` below always causes), which would skip
    # build-time validation of the RPZ zonefiles below.
    checkconf = lib.mkForce true;

    # Unix-socket-only control channel for `unbound-control`. Not used by
    # this file directly (the RPZ zones below are file+reload based, not
    # unbound-control -- see the leases zone's comment for why), but
    # harmless to leave enabled for ad-hoc debugging (`unbound-control
    # list_local_zones` etc).
    localControlSocketPath = "/run/unbound/unbound.ctl";

    settings = {
      remote-control.control-use-cert = false;

      server = {
        # Bind explicitly to each dns-server-enabled interface's own
        # address — never `0.0.0.0` — so this never becomes reachable
        # from WAN.
        interface = lib.forEach cfgSetDnsServerInterfaceOnly (
          dhcp_interface_conf: (ipv4_fn.fromCidrString dhcp_interface_conf.dhcp.server.address).address
        );

        access-control = [
          "127.0.0.0/8 allow"
        ]
        ++ lib.forEach cfgSetDnsServerInterfaceOnly (
          dhcp_interface_conf:
          let
            cidr = ipv4_fn.fromCidrString dhcp_interface_conf.dhcp.server.address;
          in
          "${cidr.network}/${builtins.toString cidr.prefix} allow"
        );
      }
      // lib.optionalAttrs (spoofEnabled || leaseHookEnabled) {
        # RPZ (spoof.overrides / spoof.blocklist / the DHCP-lease-derived
        # records below) requires the respip module, and is scoped to
        # `trust = "lan"` clients only via the "lan" tag -- a
        # `trust = "forward-only"` interface's subnet is deliberately
        # left untagged, so it never matches.
        module-config = ''"respip validator iterator"'';
        define-tag = ''"lan"'';
        access-control-tag = lib.forEach lanInterfaces (
          dhcp_interface_conf:
          let
            cidr = ipv4_fn.fromCidrString dhcp_interface_conf.dhcp.server.address;
          in
          ''${cidr.network}/${builtins.toString cidr.prefix} "lan"''
        );
      };

      # Anything not answered locally is forwarded to resolved's stub,
      # which already aggregates the correct upstream DNS servers per
      # link (DHCP-client leases automatically, static interfaces via the
      # existing `dhcp.static.dns-servers` option) — no need to duplicate
      # that logic here.
      forward-zone = [
        {
          name = ".";
          forward-addr = [ "127.0.0.53" ];
        }
      ];
    }
    // lib.optionalAttrs (rpzZones != [ ]) {
      rpz = rpzZones;
    };
  };

  systemd.services.dns-server-blocklist-update = lib.mkIf spoofBlocklistEnabled {
    description = "Fetch and convert the DNS spoof blocklist into an RPZ zone";
    after = [
      "network-online.target"
      "unbound.service"
    ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = blocklistStateDirectory;
      ExecStart = "${blocklistUpdateScript}/bin/dns-server-blocklist-update ${blocklistRpzFile} ${lib.concatStringsSep " " cfg.dns-server.spoof.blocklist.urls}";
    };
  };

  systemd.timers.dns-server-blocklist-update = lib.mkIf spoofBlocklistEnabled {
    description = "Periodic DNS spoof blocklist update";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnCalendar = cfg.dns-server.spoof.blocklist.updateInterval;
      RandomizedDelaySec = "10m";
      Persistent = true;
    };
  };

  my.router.dhcp.server.hooksLibraries.run_script."dns-server-lease-hook" =
    lib.mkIf leaseHookEnabled
      {
        path = "${leaseHookScript}/bin/dns-server-lease-hook";
        # Matches this script's own internal `case "$hook_point" in` --
        # no `environment` needed, its config is already baked in above
        # via `leaseHookScript`'s own `runtimeEnv`.
        triggers = [
          "leases4_committed"
          "lease4_expire"
          "lease4_release"
        ];
      };

  # kea-dhcp4-server's DynamicUser sandbox has no D-Bus/systemctl access
  # (see dns-server-lease-hook.sh) and its own state dir is unreadable to
  # the unbound user regardless (see leasesKeaStateDirectory's comment
  # above) -- this root-owned pair notices the Kea-side file change, syncs
  # it out to leasesSharedFile, and reloads unbound.
  systemd.paths.dns-server-leases-reload = lib.mkIf leaseHookEnabled {
    description = "Watch for DHCP-lease-derived DNS record changes";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathModified = leasesKeaFile;
      Unit = "dns-server-leases-reload.service";
    };
  };

  systemd.services.dns-server-leases-reload = lib.mkIf leaseHookEnabled {
    description = "Sync DHCP-lease-derived DNS records out of Kea's private state dir and reload unbound";
    after = [ "unbound.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${leasesSyncScript}/bin/dns-server-leases-sync";
    };
  };
})
