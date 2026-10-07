{
  pkgs ? import <nixpkgs> { },
  nixosModule ? ../.,
}:
pkgs.testers.nixosTest {
  name = "router-dhcp-client-use-routes";

  # router1 (DHCP server side) advertises BOTH a gateway (option 3) and a
  # classless static route (option 121, to its own eth2 subnet) on eth1.
  # router2's eth1 is a DHCP client on that same link, but is NOT its
  # `defaultRouteInterface` -- `dhcp.client.useRoutes = true;` proves it can
  # take the route without also taking the gateway.
  nodes = {
    router1 = { ... }: {
      imports = [ nixosModule.nixosModules.default ];

      virtualisation.vlans = [
        1
        2
      ];

      networking.useDHCP = false;

      my.router = {
        enable = true;

        configInterface = {
          eth1 = {
            mac = null;
            dhcp.server = {
              id = 100;
              address = "10.0.2.1/24";
              firstIP = 10;
              default-route = true;
              classless-static-route = true;
            };
          };
          eth2 = {
            mac = null;
            dhcp.server = {
              id = 200;
              address = "192.168.99.1/24";
              firstIP = 10;
              default-route = false;
            };
          };
        };
      };
    };

    router2 = { ... }: {
      imports = [ nixosModule.nixosModules.default ];

      virtualisation.vlans = [
        1
        3
      ];

      networking.useDHCP = false;

      my.router = {
        enable = true;
        defaultRouteInterface = "eth2";

        configInterface = {
          eth1 = {
            mac = null;
            dhcp.client.useRoutes = true;
          };
          eth2 = {
            mac = null;
            dhcp.static = {
              ip-address = "10.0.3.1/24";
              gateway = null;
            };
          };
        };
      };
    };
  };

  testScript =
    # python
    ''
      import json

      start_all()

      router1.wait_for_unit("multi-user.target")
      router1.wait_for_unit("systemd-networkd.service")
      router1.wait_for_unit("kea-dhcp4-server.service")

      router2.wait_for_unit("multi-user.target")
      router2.wait_for_unit("systemd-networkd.service")

      # Give the DHCP client time to complete its lease (matches the
      # fixed-sleep pattern used by tests/dhcp-server.nix).
      router2.sleep(5)

      with subtest("router2 gets a DHCP lease on eth1"):
          addr_info = json.loads(router2.succeed("ip --json addr show eth1"))
          ipv4_addrs = [a for a in addr_info[0]["addr_info"] if a["family"] == "inet"]
          assert len(ipv4_addrs) > 0, "eth1 should have a DHCP-leased IPv4 address"

      with subtest("router2 installs the classless static route via eth1"):
          routes = json.loads(router2.succeed("ip --json route show"))
          lan_routes = [
              r for r in routes
              if r.get("dst") == "192.168.99.0/24" and r.get("dev") == "eth1"
          ]
          assert len(lan_routes) == 1, f"expected exactly one route to 192.168.99.0/24 via eth1, got: {routes}"

      with subtest("router2 does NOT take a default route via eth1"):
          routes = json.loads(router2.succeed("ip --json route show"))
          default_via_eth1 = [
              r for r in routes
              if r.get("dst") == "default" and r.get("dev") == "eth1"
          ]
          assert len(default_via_eth1) == 0, f"no default route should exist via eth1, got: {routes}"

      with subtest("router2's defaultRouteInterface (eth2) still has its static address"):
          addr_info = json.loads(router2.succeed("ip --json addr show eth2"))
          ipv4_addrs = [a for a in addr_info[0]["addr_info"] if a["family"] == "inet"]
          assert len(ipv4_addrs) > 0, "eth2 should still have its static IPv4 address"

      with subtest("router2 can reach router1's extra subnet through the installed route"):
          router2.succeed("ping -c 3 192.168.99.1")
    '';
}
