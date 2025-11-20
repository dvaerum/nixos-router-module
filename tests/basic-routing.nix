{ pkgs ? import <nixpkgs> {}
, nixosModule ? ../.
}:

let
  inherit (pkgs) lib;
in

pkgs.nixosTest {
  name = "router-basic-routing";

  nodes = {
    router = { config, pkgs, ... }: {
      imports = [ nixosModule.nixosModules.default ];

      virtualisation.vlans = [ 1 2 ];

      networking.useDHCP = false;

      my.router = {
        enable = true;
        defaultRouteInterface = "eth1";

        configInterface = [
          {
            name = "eth1";
            mac = null;
            dhcp = {
              static = {
                ip-address = "10.0.1.2/24";
                gateway = null;
              };
            };
            ipMasquerade = true;
            forwarding = true;
          }
          {
            name = "eth2";
            mac = null;
            dhcp = {
              static = {
                ip-address = "192.168.100.1/24";
                gateway = null;
              };
            };
            forwarding = true;
          }
        ];
      };
    };

    # External "internet" node
    external = { ... }: {
      virtualisation.vlans = [ 1 ];
      networking.interfaces.eth1.ipv4.addresses = [{
        address = "10.0.1.1";
        prefixLength = 24;
      }];
      networking.firewall.enable = false;

      # Simple HTTP server to test connectivity
      services.nginx = {
        enable = true;
        virtualHosts."_" = {
          root = pkgs.writeTextDir "index.html" "External Server";
        };
      };
    };

    # Internal client
    client = { ... }: {
      virtualisation.vlans = [ 2 ];
      networking.interfaces.eth1.ipv4.addresses = [{
        address = "192.168.100.10";
        prefixLength = 24;
      }];
      networking.defaultGateway = {
        address = "192.168.100.1";
        interface = "eth1";
      };
      networking.firewall.enable = false;
    };
  };

  testScript = ''
    import json

    start_all()

    # Wait for all machines to be ready
    router.wait_for_unit("multi-user.target")
    external.wait_for_unit("multi-user.target")
    client.wait_for_unit("multi-user.target")

    # Wait for network to be configured
    router.wait_for_unit("systemd-networkd.service")
    external.wait_for_unit("nginx.service")

    with subtest("Router eth1 has IPv4 address"):
        addr_info = json.loads(router.succeed("ip --json addr show eth1"))
        ipv4_addrs = [addr for addr in addr_info[0]["addr_info"] if addr["family"] == "inet"]
        assert len(ipv4_addrs) > 0, "eth1 should have at least one IPv4 address"

    with subtest("Router eth2 has correct static IP"):
        addr_info = json.loads(router.succeed("ip --json addr show eth2"))
        ipv4_addrs = [
            addr for addr in addr_info[0]["addr_info"]
            if addr.get("local") == "192.168.100.1" and addr.get("prefixlen") == 24
        ]
        assert len(ipv4_addrs) == 1, "eth2 should have 192.168.100.1/24"

    with subtest("Client can reach router"):
        client.succeed("ping -c 3 192.168.100.1")

    with subtest("nftables masquerade rules exist"):
        router.succeed("nft list table ip masquerade-ip-address")
        output = router.succeed("nft list table ip masquerade-ip-address")
        assert "masquerade" in output, "Masquerade rule should be present"

    with subtest("Router has correct routing table"):
        routes = json.loads(router.succeed("ip --json route show"))
        lan_routes = [r for r in routes if r.get("dst") == "192.168.100.0/24"]
        assert len(lan_routes) > 0, "Route for 192.168.100.0/24 should exist"
  '';
}
