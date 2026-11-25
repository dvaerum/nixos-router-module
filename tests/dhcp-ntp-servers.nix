{
  pkgs ? import <nixpkgs> { },
  nixosModule ? ../.,
}:
###########################################################################
# Pure-eval check (no VM): the NTP servers Kea advertises (option 42).
#
# `dhcp.server.generalSettings.ntpServers` is the value for every subnet and
# `<interface>.dhcp.server.ntp-servers` overrides it for one: a subnet's own
# value if set, else the global one, else the subnet's own router address;
# [ ] advertises nothing. What a client actually receives is covered by the
# `dhcp-ntp-servers-wire` VM test.
###########################################################################
let
  inherit (pkgs) lib;

  # Two subnets so one run shows both an inheriting and an overriding one.
  render =
    {
      global ? null,
      first ? null,
      second ? null,
    }:
    let
      evaluated = pkgs.nixos {
        imports = [ nixosModule.nixosModules.default ];
        my.router = {
          enable = true;
          dhcp.server.generalSettings = lib.optionalAttrs (global != null) { ntpServers = global; };
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

  globalListed = render { global = [ "203.0.113.50" ]; };
  globalNone = render { global = [ ]; };
  globalListedSubnetOverride = render {
    global = [ "203.0.113.50" ];
    first = [ "203.0.113.10" ];
  };
  globalNoneSubnetOverride = render {
    global = [ ];
    first = [ "203.0.113.10" ];
  };
  globalListedSubnetNone = render {
    global = [ "203.0.113.50" ];
    first = [ ];
  };

  checks = [
    {
      name = "global list: every subnet that does not override it advertises the global list";
      ok = globalListed.dataOf 1 == "203.0.113.50" && globalListed.dataOf 2 == "203.0.113.50";
    }
    {
      name = "global empty list: no subnet advertises an NTP server";
      ok = globalNone.dataOf 1 == null && globalNone.dataOf 2 == null;
    }
    {
      name = "a subnet list overrides the global list, the other subnet keeps the global one";
      ok =
        globalListedSubnetOverride.dataOf 1 == "203.0.113.10"
        && globalListedSubnetOverride.dataOf 2 == "203.0.113.50";
    }
    {
      name = "a subnet list overrides a global empty list";
      ok =
        globalNoneSubnetOverride.dataOf 1 == "203.0.113.10" && globalNoneSubnetOverride.dataOf 2 == null;
    }
    {
      name = "a subnet empty list overrides the global list (no NTP there, the other subnet inherits)";
      ok = globalListedSubnetNone.dataOf 1 == null && globalListedSubnetNone.dataOf 2 == "203.0.113.50";
    }
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
