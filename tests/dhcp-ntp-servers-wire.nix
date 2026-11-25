{
  pkgs ? import <nixpkgs> { },
  nixosModule ? ../.,
}:
###########################################################################
# NTP servers in the DHCP offer, on the wire
###########################################################################
#
#   router (vlans 1-3)                          client (one NIC per vlan)
#     eth1 192.0.2.1/24      default              asks for option 42 in its
#     eth2 198.51.100.1/24   ntp-servers = [ a ]  DISCOVER and prints what the
#     eth3 192.0.3.1/24      ntp-servers = [ ]    OFFER carries
#
# The default advertises the router itself, so that address must also have the
# router's NTP server listening on it; an explicit list is passed through
# unchanged; an empty list leaves option 42 out. The generated config is
# covered by the `dhcp-ntp-servers` check.
###########################################################################
let
  offerClient = pkgs.writers.writePython3Bin "dhcp-offer-ntp-client" {
    # Long lines are fine in a test script.
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./dhcp-offer-ntp-client.py);
  ntpClient = pkgs.writers.writePython3Bin "ntp-query-client" {
    # Long lines are fine in a test script.
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./ntp-query-client.py);
in
{
  vm = pkgs.testers.nixosTest {
    name = "router-dhcp-ntp-servers";
    skipLint = false;

    nodes = {
      router =
        { ... }:
        {
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
                dhcp.server = {
                  id = 1;
                  address = "192.0.2.1/24";
                };
              };
              eth2 = {
                mac = null;
                dhcp.server = {
                  id = 2;
                  address = "198.51.100.1/24";
                  ntp-servers = [ "203.0.113.123" ];
                };
              };
              eth3 = {
                mac = null;
                dhcp.server = {
                  id = 3;
                  address = "192.0.3.1/24";
                  ntp-servers = [ ];
                };
              };
            };
          };
        };

      client =
        { ... }:
        {
          virtualisation.vlans = [
            1
            2
            3
          ];
          networking.useDHCP = false;
          networking.firewall.enable = false;
          environment.systemPackages = [
            offerClient
            pkgs.iproute2
          ];
        };
    };

    testScript = ''
      router.start()
      router.wait_for_unit("multi-user.target")
      router.wait_for_unit("kea-dhcp4-server.service")
      router.wait_for_unit("ntpd.service")

      client.start()
      client.wait_for_unit("multi-user.target")

      with subtest("default: the offer advertises the router itself"):
          out = client.succeed("dhcp-offer-ntp-client eth1")
          assert "iface=eth1 ntp=192.0.2.1" in out, out

      with subtest("default: the router's NTP server listens on that address"):
          router.wait_until_succeeds("ss -uln | grep -q '192.0.2.1:123'")

      with subtest("an explicit list is passed through unchanged"):
          out = client.succeed("dhcp-offer-ntp-client eth2")
          assert "iface=eth2 ntp=203.0.113.123" in out, out

      with subtest("an empty list leaves option 42 out of the offer"):
          out = client.succeed("dhcp-offer-ntp-client eth3")
          assert "iface=eth3 ntp=none" in out, out
    '';
  };

  # The same on the wire with the global handle set: one subnet inherits it,
  # one overrides it with its own list, one turns NTP off for itself.
  globalVm = pkgs.testers.nixosTest {
    name = "router-dhcp-ntp-servers-global";
    skipLint = false;

    nodes = {
      router =
        { ... }:
        {
          imports = [ nixosModule.nixosModules.default ];

          virtualisation.vlans = [
            1
            2
            3
          ];
          networking.useDHCP = false;

          my.router = {
            enable = true;
            dhcp.server.generalSettings.ntpServers = [ "203.0.113.50" ];
            configInterface = {
              eth1 = {
                mac = null;
                dhcp.server = {
                  id = 1;
                  address = "192.0.2.1/24";
                };
              };
              eth2 = {
                mac = null;
                dhcp.server = {
                  id = 2;
                  address = "198.51.100.1/24";
                  ntp-servers = [ "203.0.113.123" ];
                };
              };
              eth3 = {
                mac = null;
                dhcp.server = {
                  id = 3;
                  address = "192.0.3.1/24";
                  ntp-servers = [ ];
                };
              };
            };
          };
        };

      client =
        { ... }:
        {
          virtualisation.vlans = [
            1
            2
            3
          ];
          networking.useDHCP = false;
          networking.firewall.enable = false;
          environment.systemPackages = [
            offerClient
            pkgs.iproute2
          ];
        };
    };

    testScript = ''
      router.start()
      router.wait_for_unit("multi-user.target")
      router.wait_for_unit("kea-dhcp4-server.service")

      client.start()
      client.wait_for_unit("multi-user.target")

      with subtest("a subnet without its own value advertises the global list"):
          out = client.succeed("dhcp-offer-ntp-client eth1")
          assert "iface=eth1 ntp=203.0.113.50" in out, out

      with subtest("a subnet's own list overrides the global one"):
          out = client.succeed("dhcp-offer-ntp-client eth2")
          assert "iface=eth2 ntp=203.0.113.123" in out, out

      with subtest("a subnet set to an empty list advertises nothing despite the global list"):
          out = client.succeed("dhcp-offer-ntp-client eth3")
          assert "iface=eth3 ntp=none" in out, out
    '';
  };

  # Whether the router's NTP server answers a subnet, on the wire: on by
  # default, switched off for one subnet with ntpServerEnable = false. A real
  # NTP request must be answered on the first and ignored on the second, and
  # the offer must advertise the router only where it answers.
  serveVm = pkgs.testers.nixosTest {
    name = "router-dhcp-ntp-server-enable";
    skipLint = false;

    nodes = {
      router =
        { ... }:
        {
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
                  id = 1;
                  address = "192.0.2.1/24";
                };
              };
              eth2 = {
                mac = null;
                dhcp.server = {
                  id = 2;
                  address = "198.51.100.1/24";
                  ntpServerEnable = false;
                };
              };
            };
          };
        };

      client =
        { ... }:
        {
          virtualisation.vlans = [
            1
            2
          ];
          networking.useDHCP = false;
          networking.firewall.enable = false;
          environment.systemPackages = [
            offerClient
            ntpClient
            pkgs.iproute2
          ];
        };
    };

    testScript = ''
      router.start()
      router.wait_for_unit("multi-user.target")
      router.wait_for_unit("kea-dhcp4-server.service")
      router.wait_for_unit("ntpd.service")

      client.start()
      client.wait_for_unit("multi-user.target")

      with subtest("subnet with NTP on: the offer advertises the router and ntpd answers a request"):
          out = client.succeed("dhcp-offer-ntp-client eth1")
          assert "iface=eth1 ntp=192.0.2.1" in out, out
          out = client.succeed("ntp-query-client eth1 192.0.2.1")
          assert "reply=yes" in out, out

      with subtest("subnet with NTP off: nothing is advertised and ntpd ignores a request"):
          out = client.succeed("dhcp-offer-ntp-client eth2")
          assert "iface=eth2 ntp=none" in out, out
          out = client.succeed("ntp-query-client eth2 198.51.100.1")
          assert "reply=no" in out, out
    '';
  };
}
