{
  pkgs ? import <nixpkgs> { },
  nixosModule ? ../.,
}:
let
  inherit (pkgs) lib;
in
pkgs.testers.nixosTest {
  name = "router-dhcp-server";

  nodes = {
    router = { ... }: {
      imports = [ nixosModule.nixosModules.default ];

      virtualisation.vlans = [
        1
        2
        3
      ];

      networking.useDHCP = false;

      my.router = {
        enable = true;

        configInterface = {
          eth1 = {
            mac = null;
            dhcp = {
              server = {
                id = 100;
                address = "192.168.50.1/24";
                firstIP = 10;
                default-route = true;
                domainName = [ "test.local" ];
                reservations = {
                  "52:54:00:12:34:56" = {
                    ip-address = "192.168.50.100";
                  };
                };
              };
            };
            forwarding = true;
          };
          eth2 = {
            mac = null;
            dhcp = {
              server = {
                id = 200;
                address = "192.168.60.1/24";
                # Advertise a DIFFERENT gateway + DNS than the router itself
                # (which sits at 192.168.60.1) — this is the decoupling.
                gateway = "192.168.60.254";
                dns-servers = [ "192.168.60.53" ];
                firstIP = 10;
              };
            };
            forwarding = true;
          };
          eth3 = {
            mac = null;
            dhcp = {
              server = {
                id = 300;
                address = "192.168.70.1/24";
                # Opt out of advertising a gateway and DNS entirely.
                default-route = false;
                dns-servers = [ ];
                firstIP = 10;
              };
            };
            forwarding = true;
          };
        };
      };
    };

    # DHCP client without reservation
    client1 = { ... }: {
      virtualisation.vlans = [ 1 ];
      networking.useDHCP = false;
      networking.interfaces.eth1 = {
        useDHCP = true;
        ipv4.addresses = lib.mkForce [ ]; # Remove configured IP addresses
      };
      networking.firewall.enable = false;
    };

    # DHCP client with MAC matching reservation
    client2 = { ... }: {
      virtualisation.vlans = [ 1 ];
      networking.useDHCP = false;
      networking.interfaces.eth1 = {
        useDHCP = true;
        macAddress = "52:54:00:12:34:56";
        ipv4.addresses = lib.mkForce [ ]; # Remove configured IP addresses
      };
      networking.firewall.enable = false;
    };

    # DHCP client on the override subnet: must receive the advertised gateway
    # (192.168.60.254) and DNS (192.168.60.53), NOT the router's own address.
    client3 = { ... }: {
      virtualisation.vlans = [ 2 ];
      networking.useDHCP = false;
      networking.interfaces.eth1 = {
        useDHCP = true;
        ipv4.addresses = lib.mkForce [ ];
      };
      networking.firewall.enable = false;
    };

    # DHCP client on the opt-out subnet: gets an IP but NO gateway and NO
    # server-provided DNS (default-route = false, dns-servers = []).
    client4 = { ... }: {
      virtualisation.vlans = [ 3 ];
      networking.useDHCP = false;
      networking.interfaces.eth1 = {
        useDHCP = true;
        ipv4.addresses = lib.mkForce [ ];
      };
      networking.firewall.enable = false;
    };
  };

  testScript =
    # python
    ''
      import json

      start_all()

      # Wait for router to be ready
      router.wait_for_unit("multi-user.target")
      router.wait_for_unit("systemd-networkd.service")
      router.wait_for_unit("kea-dhcp4-server.service")

      with subtest("Router interface is configured correctly"):
          addr_info = json.loads(router.succeed("ip --json addr show eth1"))
          ipv4_addrs = [
              addr for addr in addr_info[0]["addr_info"]
              if addr.get("local") == "192.168.50.1" and addr.get("prefixlen") == 24
          ]
          assert len(ipv4_addrs) == 1, "eth1 should have 192.168.50.1/24"

      with subtest("Kea DHCP server is running"):
          router.succeed("systemctl is-active kea-dhcp4-server.service")

      # Wait for clients to get DHCP
      client1.wait_for_unit("multi-user.target")
      client2.wait_for_unit("multi-user.target")
      client3.wait_for_unit("multi-user.target")
      client4.wait_for_unit("multi-user.target")

      # Give DHCP clients time to get addresses
      client1.sleep(5)
      client2.sleep(5)
      client3.sleep(5)
      client4.sleep(5)

      with subtest("Client without reservation gets IP from pool"):
          # Should get IP >= 192.168.50.10 (firstIP setting)
          addr_info = json.loads(client1.succeed("ip --json addr show eth1"))
          ipv4_addrs = [addr for addr in addr_info[0]["addr_info"] if addr["family"] == "inet"]
          assert len(ipv4_addrs) > 0, "Client should have IPv4 address"

          ip1 = ipv4_addrs[0]["local"]
          assert ip1.startswith("192.168.50."), f"Client IP {ip1} should be in 192.168.50.0/24"
          assert int(ip1.split('.')[-1]) >= 10, f"Client IP {ip1} should be >= 192.168.50.10"

      with subtest("Client with reservation gets reserved IP"):
          # Should get the reserved IP 192.168.50.100
          addr_info = json.loads(client2.succeed("ip --json addr show eth1"))
          ipv4_addrs = [addr for addr in addr_info[0]["addr_info"] if addr.get("local") == "192.168.50.100"]
          assert len(ipv4_addrs) == 1, "Client2 should have reserved IP 192.168.50.100"

      with subtest("Clients get correct gateway"):
          # Both clients should have default route via 192.168.50.1
          routes1 = json.loads(client1.succeed("ip --json route show"))
          default_routes1 = [r for r in routes1 if r.get("dst") == "default" and r.get("gateway") == "192.168.50.1"]
          assert len(default_routes1) > 0, "Client1 should have default route via 192.168.50.1"

          routes2 = json.loads(client2.succeed("ip --json route show"))
          default_routes2 = [r for r in routes2 if r.get("dst") == "default" and r.get("gateway") == "192.168.50.1"]
          assert len(default_routes2) > 0, "Client2 should have default route via 192.168.50.1"

      with subtest("Clients can reach router"):
          client1.succeed("ping -c 3 192.168.50.1")
          client2.succeed("ping -c 3 192.168.50.1")

      with subtest("Clients can reach each other"):
          client1.succeed("ping -c 3 192.168.50.100")
          client2.succeed(f"ping -c 3 {ip1}")

      with subtest("DNS configuration is correct"):
          # Clients should have DNS server set to router IP
          resolv1 = client1.succeed("cat /etc/resolv.conf")
          assert "nameserver 192.168.50.1" in resolv1, "Client1 should have router as DNS server"
          assert "test.local" in resolv1, "Client1 should have test.local domain"

          resolv2 = client2.succeed("cat /etc/resolv.conf")
          assert "nameserver 192.168.50.1" in resolv2, "Client2 should have router as DNS server"
          assert "test.local" in resolv2, "Client2 should have test.local domain"

      with subtest("Override subnet: client gets a DIFFERENT gateway and DNS than the router"):
          # Router sits at 192.168.60.1 but advertises gateway .254 and DNS .53.
          addr3 = json.loads(client3.succeed("ip --json addr show eth1"))
          ips3 = [a["local"] for a in addr3[0]["addr_info"] if a["family"] == "inet"]
          assert ips3 and ips3[0].startswith("192.168.60."), f"client3 should get a 192.168.60.x address, got {ips3}"

          routes3 = json.loads(client3.succeed("ip --json route show"))
          gw3 = [r.get("gateway") for r in routes3 if r.get("dst") == "default"]
          assert "192.168.60.254" in gw3, f"client3 default route should be via 192.168.60.254 (override), got {gw3}"
          assert "192.168.60.1" not in gw3, "client3 must NOT use the router (192.168.60.1) as gateway"

          resolv3 = client3.succeed("cat /etc/resolv.conf")
          assert "nameserver 192.168.60.53" in resolv3, f"client3 DNS should be 192.168.60.53 (override): {resolv3}"
          assert "nameserver 192.168.60.1" not in resolv3, "client3 must NOT use the router (192.168.60.1) as DNS"

      with subtest("Opt-out subnet: client gets an IP but NO gateway and NO server DNS"):
          # default-route = false and dns-servers = [] -> advertise neither.
          addr4 = json.loads(client4.succeed("ip --json addr show eth1"))
          ips4 = [a["local"] for a in addr4[0]["addr_info"] if a["family"] == "inet"]
          assert ips4 and ips4[0].startswith("192.168.70."), f"client4 should get a 192.168.70.x address, got {ips4}"

          routes4 = json.loads(client4.succeed("ip --json route show"))
          default4 = [r for r in routes4 if r.get("dst") == "default"]
          assert default4 == [], f"client4 should have NO default route (default-route = false), got {default4}"

          resolv4 = client4.succeed("cat /etc/resolv.conf")
          assert "nameserver 192.168.70.1" not in resolv4, "client4 must NOT be given the router as DNS (dns-servers = [])"

      with subtest("Kea lease database has entries"):
          router.succeed("test -f /var/lib/kea/dhcp4.leases")
          leases = router.succeed("cat /var/lib/kea/dhcp4.leases")
          assert "192.168.50" in leases, "Lease database should contain entries for 192.168.50 network"
    '';
}
