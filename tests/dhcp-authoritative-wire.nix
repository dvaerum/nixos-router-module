{
  pkgs ? import <nixpkgs> { },
  nixosModule ? ../.,
}:
###########################################################################
# Kea `authoritative` on the wire
###########################################################################
#
#   +---------------------------------------------------------------+
#   |  router (vlans 1 + 2), global authoritative = true (default)  |
#   |    eth1: 192.0.2.1/24      inherits the global value          |
#   |    eth2: 198.51.100.1/24   dhcp.server.authoritative = false  |
#   +---------------------------------------------------------------+
#                 |  vlan 1                      |  vlan 2
#               client (eth1)                  client (eth2)
#
# The client asks each server to confirm an address it never leased (a
# DHCPREQUEST in the INIT-REBOOT state). An authoritative Kea refuses it with a
# DHCPNAK straight away; a non-authoritative one stays silent. The two subnets
# differ only in the per-subnet override, so a NAK on eth1 and silence on eth2
# shows both that the global default is on and that the override is applied.
# The generated JSON is covered by the `dhcp-authoritative` check.
###########################################################################
let
  requestClient = pkgs.writers.writePython3Bin "dhcp-unknown-renewal-client" {
    # Long lines are fine in a test script.
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./dhcp-unknown-renewal-client.py);
in
{
  vm = pkgs.testers.nixosTest {
    name = "router-dhcp-authoritative";
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
                  authoritative = false;
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
            requestClient
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

      with subtest("authoritative subnet (inherits the global default): a stale address gets a NAK"):
          out = client.succeed("dhcp-unknown-renewal-client eth1 192.0.2.99")
          assert "iface=eth1 reply=NAK" in out, out

      with subtest("subnet overridden to non-authoritative: a stale address gets no answer"):
          out = client.succeed("dhcp-unknown-renewal-client eth2 198.51.100.99")
          assert "iface=eth2 reply=none" in out, out
    '';
  };
}
