{
  pkgs ? import <nixpkgs> { },
  nixosModule ? ../.,
}:
###########################################################################
# Pure-eval check (no VM): the NTP servers Kea advertises (option 42).
#
# `<interface>.dhcp.server.ntp-servers` mirrors `dns-servers`: null (default)
# advertises the router's own address, [ ] advertises nothing, a list
# advertises exactly those servers. What a client actually receives is covered
# by the `dhcp-ntp-servers-wire` VM test.
###########################################################################
let
  inherit (pkgs) lib;

  # Two subnets so one run shows both an inheriting and an overriding one.
  render =
    {
      first ? null,
      second ? null,
    }:
    let
      evaluated = pkgs.nixos {
        imports = [ nixosModule.nixosModules.default ];
        my.router = {
          enable = true;
          configInterface = {
            eth1 = {
              mac = null;
              dhcp.server = {
                id = 1;
                address = "192.0.2.1/24";
              }
              // lib.optionalAttrs (first != null) { ntp-servers = first; };
            };
            eth2 = {
              mac = null;
              dhcp.server = {
                id = 2;
                address = "198.51.100.1/24";
              }
              // lib.optionalAttrs (second != null) { ntp-servers = second; };
            };
          };
        };
      };
      # nixpkgs renders the Kea config in a build step; `.source` has to be
      # realised (import-from-derivation) to read it. The string context is
      # dropped only because these values are just compared here.
      text = builtins.readFile evaluated.config.environment.etc."kea/dhcp4-server.conf".source;
      kea = (builtins.fromJSON (builtins.unsafeDiscardStringContext text)).Dhcp4;
      subnetFor = id: lib.findFirst (s: s.id == id) null kea.subnet4;
      optionOf =
        id: lib.findFirst (o: o.name == "ntp-servers") null ((subnetFor id)."option-data" or [ ]);
    in
    {
      # null when no ntp-servers option is advertised on that subnet.
      dataOf = id: (optionOf id).data or null;
    };

  default = render { };
  listed = render {
    first = [
      "203.0.113.10"
      "203.0.113.11"
    ];
  };
  none = render { first = [ ]; };
  mixed = render {
    first = [ "203.0.113.10" ];
    second = [ ];
  };

  checks = [
    {
      name = "default: each subnet advertises its own router address";
      ok = default.dataOf 1 == "192.0.2.1" && default.dataOf 2 == "198.51.100.1";
    }
    {
      name = "a list is advertised exactly, comma separated";
      ok = listed.dataOf 1 == "203.0.113.10, 203.0.113.11";
    }
    {
      name = "a list on one subnet leaves the other on its router address";
      ok = listed.dataOf 2 == "198.51.100.1";
    }
    {
      name = "an empty list advertises no NTP server on that subnet";
      ok = none.dataOf 1 == null;
    }
    {
      name = "an empty list on one subnet leaves the other on its router address";
      ok = none.dataOf 2 == "198.51.100.1";
    }
    {
      name = "different settings on two subnets are each rendered as set";
      ok = mixed.dataOf 1 == "203.0.113.10" && mixed.dataOf 2 == null;
    }
  ];

  failures = builtins.filter (c: !c.ok) checks;
in
pkgs.runCommand "dhcp-ntp-servers-check" { } (
  if failures == [ ] then
    "touch $out"
  else
    throw "dhcp-ntp-servers check(s) failed: ${builtins.toJSON (map (f: f.name) failures)}"
)
