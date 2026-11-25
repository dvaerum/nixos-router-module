{
  pkgs ? import <nixpkgs> { },
  nixosModule ? ../.,
}:
###########################################################################
# Pure-eval check (no VM): the Kea `authoritative` setting.
#
# `my.router.dhcp.server.generalSettings.authoritative` (default true) is the
# global value; `<interface>.dhcp.server.authoritative` (default null) overrides
# it for one subnet and is only rendered into that subnet's Kea block when set,
# so an unset subnet inherits the global value inside Kea itself. What the
# server then does on the wire is tested by the `dhcp-authoritative` VM test.
###########################################################################
let
  inherit (pkgs) lib;

  # Two subnets so one run can show both an inheriting and an overriding one.
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
          dhcp.server.generalSettings = lib.optionalAttrs (global != null) { authoritative = global; };
          configInterface = {
            eth1 = {
              mac = null;
              dhcp.server = {
                id = 1;
                address = "192.0.2.1/24";
              }
              // lib.optionalAttrs (first != null) { authoritative = first; };
            };
            eth2 = {
              mac = null;
              dhcp.server = {
                id = 2;
                address = "198.51.100.1/24";
              }
              // lib.optionalAttrs (second != null) { authoritative = second; };
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
    in
    {
      global = kea.authoritative or null;
      first = (subnetFor 1).authoritative or null;
      second = (subnetFor 2).authoritative or null;
      hasKey = id: (subnetFor id) ? authoritative;
    };

  default = render { };
  globalOff = render { global = false; };
  onlyFirstOff = render { first = false; };
  globalOffFirstOn = render {
    global = false;
    first = true;
  };
  mixed = render {
    first = true;
    second = false;
  };

  checks = [
    {
      name = "default: the global value is true";
      ok = default.global == true;
    }
    {
      name = "default: no subnet carries its own authoritative key (they inherit)";
      ok = !(default.hasKey 1) && !(default.hasKey 2);
    }
    {
      name = "global off: the global value is false";
      ok = globalOff.global == false;
    }
    {
      name = "global off: still no subnet key";
      ok = !(globalOff.hasKey 1) && !(globalOff.hasKey 2);
    }
    {
      name = "subnet false under the default global: that subnet is false, the other inherits";
      ok = onlyFirstOff.global == true && onlyFirstOff.first == false && !(onlyFirstOff.hasKey 2);
    }
    {
      name = "subnet true under global off: that subnet is true, the other inherits";
      ok =
        globalOffFirstOn.global == false && globalOffFirstOn.first == true && !(globalOffFirstOn.hasKey 2);
    }
    {
      name = "two subnets with different overrides are each rendered as set";
      ok = mixed.first == true && mixed.second == false;
    }
  ];

  failures = builtins.filter (c: !c.ok) checks;
in
pkgs.runCommand "dhcp-authoritative-check" { } (
  if failures == [ ] then
    "touch $out"
  else
    throw "dhcp-authoritative check(s) failed: ${builtins.toJSON (map (f: f.name) failures)}"
)
