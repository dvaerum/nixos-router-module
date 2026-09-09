{
  pkgs ? import <nixpkgs> {},
  nixosModule ? ../.,
}:
pkgs.testers.nixosTest {
  name = "router-vxlan";

  # Topology (three shared "vlans" == three separate L2 segments in the
  # test's virtual switch):
  #   vlan 1: underlay, router1.eth1 <-> router2.eth1 (already-routable
  #           "private infra" the VXLAN tunnels ride on top of)
  #   vlan 2: router1's LAN, router1.eth2 <-> client1
  #   vlan 3: router2's LAN, router2.eth2 <-> client2
  #
  # Two separate VXLAN interfaces (different VNIs) exercise the two
  # attachment modes:
  #   vxlan1000: routed mode. Carries its own static IP directly, proving
  #              the base encapsulation mechanism and Independent=true.
  #   vxlan2000: bridge mode. Joins br-lan alongside each router's eth2,
  #              proving the pure-L2-extension attachment mode (client1 and
  #              client2 end up in the SAME L2 segment despite sitting
  #              behind different routers).
  nodes = {
    router1 = {...}: {
      imports = [nixosModule.nixosModules.default];

      virtualisation.vlans = [1 2];

      networking.useDHCP = false;

      my.router = {
        enable = true;

        configInterface = [
          {
            name = "eth1";
            mac = null;
            dhcp.static.ip-address = "10.0.1.1/24";
          }
          {
            name = "eth2";
            mac = null;
            bridges = [{name = "br-lan";}];
          }
        ];

        bridgeInterfaces.br-lan = {};

        vxlanInterfaces = {
          vxlan1000 = {
            vni = 1000;
            remote = "10.0.1.2";
            dhcp.static.ip-address = "10.100.0.1/30";
          };
          vxlan2000 = {
            vni = 2000;
            remote = "10.0.1.2";
            bridges = [{name = "br-lan";}];
          };
        };
      };
    };

    router2 = {...}: {
      imports = [nixosModule.nixosModules.default];

      virtualisation.vlans = [1 3];

      networking.useDHCP = false;

      my.router = {
        enable = true;

        configInterface = [
          {
            name = "eth1";
            mac = null;
            dhcp.static.ip-address = "10.0.1.2/24";
          }
          {
            name = "eth2";
            mac = null;
            bridges = [{name = "br-lan";}];
          }
        ];

        bridgeInterfaces.br-lan = {};

        vxlanInterfaces = {
          vxlan1000 = {
            vni = 1000;
            remote = "10.0.1.1";
            dhcp.static.ip-address = "10.100.0.2/30";
          };
          vxlan2000 = {
            vni = 2000;
            remote = "10.0.1.1";
            bridges = [{name = "br-lan";}];
          };
        };
      };
    };

    client1 = {...}: {
      virtualisation.vlans = [2];
      networking.useDHCP = false;
      networking.interfaces.eth1.ipv4.addresses = [
        {
          address = "192.168.99.10";
          prefixLength = 24;
        }
      ];
      networking.firewall.enable = false;
    };

    client2 = {...}: {
      virtualisation.vlans = [3];
      networking.useDHCP = false;
      networking.interfaces.eth1.ipv4.addresses = [
        {
          address = "192.168.99.20";
          prefixLength = 24;
        }
      ];
      networking.firewall.enable = false;
    };
  };

  testScript =
    # python
    ''
      import json

      start_all()

      router1.wait_for_unit("multi-user.target")
      router2.wait_for_unit("multi-user.target")
      router1.wait_for_unit("systemd-networkd.service")
      router2.wait_for_unit("systemd-networkd.service")
      client1.wait_for_unit("multi-user.target")
      client2.wait_for_unit("multi-user.target")

      with subtest("vxlan1000 netdev exists with the configured VNI on both routers"):
          for router in [router1, router2]:
              details = json.loads(router.succeed("ip --json -details link show vxlan1000"))
              vxlan_info = details[0]["linkinfo"]["info_data"]
              assert vxlan_info["id"] == 1000, f"expected VNI 1000, got {vxlan_info.get('id')}"

      with subtest("routed mode: vxlan1000 has the configured static IP on both routers"):
          addr1 = json.loads(router1.succeed("ip --json addr show vxlan1000"))
          ips1 = [a["local"] for a in addr1[0]["addr_info"] if a["family"] == "inet"]
          assert "10.100.0.1" in ips1, f"router1 vxlan1000 should have 10.100.0.1, got {ips1}"

          addr2 = json.loads(router2.succeed("ip --json addr show vxlan1000"))
          ips2 = [a["local"] for a in addr2[0]["addr_info"] if a["family"] == "inet"]
          assert "10.100.0.2" in ips2, f"router2 vxlan1000 should have 10.100.0.2, got {ips2}"

      with subtest("routed mode: routers can ping each other across the VXLAN tunnel"):
          router1.wait_until_succeeds("ping -c 1 10.100.0.2")
          router2.succeed("ping -c 3 10.100.0.1")
          router1.succeed("ping -c 3 10.100.0.2")

      with subtest("bridge mode: vxlan2000 has no IP of its own (pure L2 member)"):
          addr = json.loads(router1.succeed("ip --json addr show vxlan2000"))
          ipv4_addrs = [a for a in addr[0]["addr_info"] if a["family"] == "inet"]
          assert ipv4_addrs == [], f"vxlan2000 should have no IPv4 address, got {ipv4_addrs}"

      with subtest("bridge mode: vxlan2000 and eth2 are both enslaved to br-lan"):
          for router in [router1, router2]:
              master = router.succeed("cat /sys/class/net/vxlan2000/master/ifindex").strip()
              eth2_master = router.succeed("cat /sys/class/net/eth2/master/ifindex").strip()
              assert master == eth2_master, "vxlan2000 and eth2 should share the same bridge master"

      with subtest("bridge mode: clients behind different routers reach each other over the stretched L2 segment"):
          client1.wait_until_succeeds("ping -c 1 192.168.99.20")
          client2.succeed("ping -c 3 192.168.99.10")
          client1.succeed("ping -c 3 192.168.99.20")
    '';
}
