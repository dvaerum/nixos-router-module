{
  pkgs ? import <nixpkgs> { },
  nixosModule ? ../.,
}:
let
  inherit (pkgs) lib;
in
{
  # Config-only test: bind addresses, per-interface enable/opt-out, and the
  # forward-only skeleton. No real DHCP-lease traffic needed for this slice.
  vm = pkgs.testers.nixosTest {
    name = "router-dns-server";

    nodes = {
      router = { ... }: {
        imports = [ nixosModule.nixosModules.default ];

        virtualisation.vlans = [
          1
          2
          3
        ];

        networking.useDHCP = false;

        environment.systemPackages = [ pkgs.bind.dnsutils ];

        # Fake blocklist source: serves a tiny hosts-format file so the
        # blocklist-update service has something to fetch without real
        # internet access (this VM test is fully offline).
        systemd.services.fake-blocklist-server = {
          description = "Fake blocklist HTTP server for the DNS spoof test";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "simple";
            WorkingDirectory = pkgs.writeTextDir "hosts" "0.0.0.0 blocked-host.nixos-router-spoof-test.com\n";
            ExecStart = "${pkgs.python3}/bin/python3 -m http.server 8088 --bind 127.0.0.1";
          };
        };

        my.router = {
          enable = true;
          dns-server = {
            enable = true;
            spoof = {
              # A plain, unreserved domain -- NOT one of the RFC 6761
              # special-use TLDs (.test, .invalid, .example, .localhost,
              # home.arpa, ...), which unbound NXDOMAINs by built-in
              # default via `local-zone`, evaluated *before* RPZ. Using
              # one of those would make this test pass for the wrong
              # reason regardless of whether spoofing actually works.
              overrides."override-host.nixos-router-spoof-test.com" = "10.9.9.9";
              blocklist = {
                enable = true;
                urls = [ "http://127.0.0.1:8088/hosts" ];
              };
            };
            # Exercises the pool-lease path end-to-end (toggle off, the
            # default, is already covered at the script-unit level).
            publish-leases.enable = true;
          };

          configInterface = {
            # Default trust ("lan"), dns-server enabled by default.
            eth1 = {
              mac = null;
              dhcp.server = {
                id = 100;
                address = "192.168.50.1/24";
                domainName = [ "nixos-router-lease-test.com" ];
                # `hostname` should always win over whatever this MAC's
                # client sends over DHCP -- client_reserved below sets a
                # DIFFERENT hostname itself, to prove the precedence.
                reservations."52:54:00:12:34:56" = {
                  ip-address = "192.168.50.100";
                  hostname = "reserved-host";
                };
              };
              forwarding = true;
            };
            # A trusted peer network (e.g. reached over a VXLAN tunnel):
            # should still be served, but with no spoof/local-data.
            eth2 = {
              mac = null;
              dhcp.server = {
                id = 200;
                address = "192.168.60.1/24";
                dns-server.trust = "forward-only";
              };
              forwarding = true;
            };
            # Per-interface opt-out: must never be bound.
            eth3 = {
              mac = null;
              dhcp.server = {
                id = 300;
                address = "192.168.70.1/24";
                dns-server.enable = false;
              };
              forwarding = true;
            };
          };
        };
      };

      # DHCP client whose MAC matches the reservation above.
      client_reserved = { ... }: {
        virtualisation.vlans = [ 1 ];
        networking.useDHCP = false;
        networking.interfaces.eth1 = {
          useDHCP = true;
          macAddress = "52:54:00:12:34:56";
          ipv4.addresses = lib.mkForce [ ]; # Remove configured IP addresses
        };
        networking.firewall.enable = false;
      };

      # Anonymous pool client, no reservation -- exercises publish-leases.enable.
      client_pool = { ... }: {
        virtualisation.vlans = [ 1 ];
        networking.useDHCP = false;
        networking.interfaces.eth1 = {
          useDHCP = true;
          ipv4.addresses = lib.mkForce [ ]; # Remove configured IP addresses
        };
        networking.firewall.enable = false;
      };
    };

    testScript =
      # python
      ''
        import json

        start_all()

        router.wait_for_unit("multi-user.target")
        router.wait_for_unit("systemd-networkd.service")
        router.wait_for_unit("unbound.service")

        with subtest("Unbound is running"):
            router.succeed("systemctl is-active unbound.service")

        with subtest("Unbound binds to lan and forward-only interfaces, never 0.0.0.0, never the opted-out interface"):
            conf = router.succeed("cat /etc/unbound/unbound.conf")
            assert "interface: 192.168.50.1" in conf, f"missing eth1 (lan) bind address:\n{conf}"
            assert "interface: 192.168.60.1" in conf, f"missing eth2 (forward-only) bind address:\n{conf}"
            assert "interface: 192.168.70.1" not in conf, f"eth3 (dns-server.enable=false) must not be bound:\n{conf}"
            assert "interface: 0.0.0.0" not in conf, f"must never bind 0.0.0.0:\n{conf}"

        with subtest("forward-only interface still resolves via resolved's stub"):
            router.succeed("dig @192.168.60.1 localhost A +short | grep -q 127.0.0.1")

        with subtest("lan interface also resolves via resolved's stub"):
            router.succeed("dig @192.168.50.1 localhost A +short | grep -q 127.0.0.1")

        with subtest("spoof.overrides returns the configured IP on a lan interface"):
            router.succeed(
                "dig @192.168.50.1 override-host.nixos-router-spoof-test.com A +short | grep -q 10.9.9.9"
            )

        with subtest("spoof.overrides is NOT applied on a forward-only interface"):
            out = router.succeed(
                "dig @192.168.60.1 override-host.nixos-router-spoof-test.com A +short +time=2 +tries=1 || true"
            )
            assert "10.9.9.9" not in out, f"forward-only interface must not see spoof.overrides:\n{out}"

        with subtest("spoof.blocklist: update service fetches, converts to RPZ, and reloads unbound"):
            router.wait_for_unit("fake-blocklist-server.service")
            router.succeed("systemctl start dns-server-blocklist-update.service")
            router.succeed("test -e /var/lib/dns-server-blocklist/blocklist.rpz")
            zone = router.succeed("cat /var/lib/dns-server-blocklist/blocklist.rpz")
            assert (
                "blocked-host.nixos-router-spoof-test.com CNAME ." in zone
            ), f"blocklist RPZ missing the fetched domain:\n{zone}"

        with subtest("spoof.blocklist blocks the domain on a lan interface (NXDOMAIN)"):
            router.succeed(
                "dig @192.168.50.1 blocked-host.nixos-router-spoof-test.com A | grep -q 'status: NXDOMAIN'"
            )

        with subtest("spoof.blocklist is NOT applied on a forward-only interface"):
            out = router.succeed(
                "dig @192.168.60.1 blocked-host.nixos-router-spoof-test.com A +time=2 +tries=1"
            )
            assert "status: NXDOMAIN" not in out, f"forward-only interface must not see spoof.blocklist:\n{out}"

        with subtest("blocklist update is idempotent: unchanged content skips the reload"):
            # mtime alone isn't reliable here (sub-second re-runs can land in
            # the same whole second and look "unchanged" even when the file
            # WAS rewritten) -- count actual reloads via the journal instead,
            # which is exactly the operation an unwanted rewrite triggers.
            reloads_before = router.succeed(
                "journalctl -u unbound.service --no-pager | grep -c 'Reloading Unbound' || true"
            ).strip()
            router.succeed("systemctl start dns-server-blocklist-update.service")
            reloads_after = router.succeed(
                "journalctl -u unbound.service --no-pager | grep -c 'Reloading Unbound' || true"
            ).strip()
            assert (
                reloads_before == reloads_after
            ), f"unchanged blocklist content must not trigger another reload: {reloads_before} -> {reloads_after}"

        client_reserved.wait_for_unit("multi-user.target")
        client_pool.wait_for_unit("multi-user.target")

        with subtest("Kea-lease hook publishes the reservation's hostname, ignoring the client's own"):
            router.wait_until_succeeds(
                "dig @192.168.50.1 reserved-host.nixos-router-lease-test.com A +short | grep -q 192.168.50.100"
            )
            # The reservation's hostname always wins -- whatever client_reserved
            # itself sends over DHCP must never make it into DNS.
            client_reserved_hostname = client_reserved.succeed("hostname").strip()
            out = router.succeed(
                f"dig @192.168.50.1 {client_reserved_hostname}.nixos-router-lease-test.com A +short +time=2 +tries=1 || true"
            )
            assert "192.168.50.100" not in out, f"client-supplied hostname must not override the reservation's:\n{out}"

        with subtest("Kea-lease hook publishes a pool client's own hostname (publish-leases.enable)"):
            pool_hostname = client_pool.succeed("hostname").strip()
            pool_addr = json.loads(client_pool.succeed("ip --json addr show eth1"))[0]["addr_info"]
            pool_ip = next(a["local"] for a in pool_addr if a["family"] == "inet")
            router.wait_until_succeeds(
                f"dig @192.168.50.1 {pool_hostname}.nixos-router-lease-test.com A +short | grep -q {pool_ip}"
            )
      '';
  };

  # Pure-eval check (no VM): the global switch fully disables the feature.
  disabledCheck =
    let
      evaluated = pkgs.nixos {
        imports = [ nixosModule.nixosModules.default ];
        my.router = {
          enable = true;
          dns-server.enable = false;
          configInterface.eth1 = {
            mac = null;
            dhcp.server = {
              id = 100;
              address = "192.168.50.1/24";
            };
          };
        };
      };
    in
    pkgs.runCommand "dns-server-disabled-check" { } (
      if evaluated.config.services.unbound.enable == false then
        "touch $out"
      else
        throw "expected services.unbound.enable == false when my.router.dns-server.enable = false, got true"
    );
}
