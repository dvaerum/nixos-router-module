{
  pkgs ? import <nixpkgs> { },
  nixosModule ? ../.,
}:

let
  inherit (pkgs) lib;
in

pkgs.nixosTest {
  name = "router-dhcp-server";

  nodes = {
    router =
      { config, pkgs, ... }:
      {
        imports = [ nixosModule.nixosModules.default ];

        virtualisation.vlans = [ 1 ];

        networking.useDHCP = false;

        my.router = {
          enable = true;

          configInterface = [
            {
              name = "eth1";
              mac = null;
              dhcp = {
                server = {
                  id = 100;
                  gateway = "192.168.50.1/24";
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
            }
          ];
        };
      };

    # DHCP client without reservation
    client1 =
      { ... }:
      {
        virtualisation.vlans = [ 1 ];
        networking.useDHCP = false;
        networking.interfaces.eth1 = {
          useDHCP = true;
          ipv4.addresses = lib.mkForce [];
        };
        networking.firewall.enable = false;
      };

    # DHCP client with MAC matching reservation
    client2 =
      { ... }:
      {
        virtualisation.vlans = [ 1 ];
        networking.useDHCP = false;
        networking.interfaces.eth1 = {
          useDHCP = true;
          macAddress = "52:54:00:12:34:56";
          ipv4.addresses = lib.mkForce [];
        };
        networking.firewall.enable = false;
      };
  };

  testScript = ''
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

    # Give DHCP clients time to get addresses
    client1.sleep(5)
    client2.sleep(5)

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

    with subtest("Kea lease database has entries"):
        router.succeed("test -f /var/lib/kea/dhcp4.leases")
        leases = router.succeed("cat /var/lib/kea/dhcp4.leases")
        assert "192.168.50" in leases, "Lease database should contain entries for 192.168.50 network"
  '';
}
