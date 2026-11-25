{
  pkgs ? import <nixpkgs> { },
  nixosModule ? ../.,
}:
###########################################################################
# Kea log severity
#
# The module used to write the severity "DEBU" (not a Kea level), so Kea
# printed `LOG_BAD_SEVERITY unrecognized log severity: DEBU` on every start and
# silently fell back to its default level. `dhcp.server.generalSettings.logSeverity`
# (default INFO) replaces it; `logDebugLevel` only applies to DEBUG.
#
# `config` is the pure-eval check of the generated config; `vm` starts Kea with
# the default and with WARN and reads its journal.
###########################################################################
let
  inherit (pkgs) lib;

  subnet = {
    mac = null;
    dhcp.server = {
      id = 1;
      address = "192.0.2.1/24";
    };
  };

  render =
    settings:
    let
      evaluated = pkgs.nixos {
        imports = [ nixosModule.nixosModules.default ];
        my.router = {
          enable = true;
          dhcp.server.generalSettings = settings;
          configInterface.eth1 = subnet;
        };
      };
      # nixpkgs renders the Kea config in a build step; `.source` has to be
      # realised (import-from-derivation) to read it. The string context is
      # dropped only because these values are just compared here.
      text = builtins.readFile evaluated.config.environment.etc."kea/dhcp4-server.conf".source;
      kea = (builtins.fromJSON (builtins.unsafeDiscardStringContext text)).Dhcp4;
    in
    lib.findFirst (l: l.name == "kea-dhcp4") null kea.loggers;

  default = render { };
  warn = render { logSeverity = "WARN"; };
  debug = render {
    logSeverity = "DEBUG";
    logDebugLevel = 50;
  };
  # A value that is not a Kea level must be rejected at evaluation time (the
  # original typo), not written into the config.
  invalid = builtins.tryEval (render { logSeverity = "DEBU"; }).severity;

  checks = [
    {
      name = "default: the severity is INFO, which is what Kea ran at before";
      ok = default.severity == "INFO";
    }
    {
      name = "default: no debuglevel key (it only applies to DEBUG)";
      ok = !(default ? debuglevel);
    }
    {
      name = "a chosen severity is written as given";
      ok = warn.severity == "WARN" && !(warn ? debuglevel);
    }
    {
      name = "DEBUG with a debug level writes both";
      ok = debug.severity == "DEBUG" && debug.debuglevel == 50;
    }
    {
      name = "the old typo \"DEBU\" is rejected at evaluation time";
      ok = !invalid.success;
    }
  ];

  failures = builtins.filter (c: !c.ok) checks;
in
{
  config = pkgs.runCommand "dhcp-kea-logging-check" { } (
    if failures == [ ] then
      "touch $out"
    else
      throw "dhcp-kea-logging check(s) failed: ${builtins.toJSON (map (f: f.name) failures)}"
  );

  vm = pkgs.testers.nixosTest {
    name = "router-dhcp-kea-logging";
    skipLint = false;

    nodes = {
      router =
        { ... }:
        {
          imports = [ nixosModule.nixosModules.default ];
          virtualisation.vlans = [ 1 ];
          networking.useDHCP = false;
          my.router = {
            enable = true;
            configInterface.eth1 = subnet;
          };
        };

      quiet =
        { ... }:
        {
          imports = [ nixosModule.nixosModules.default ];
          virtualisation.vlans = [ 1 ];
          networking.useDHCP = false;
          my.router = {
            enable = true;
            dhcp.server.generalSettings.logSeverity = "WARN";
            configInterface.eth1 = subnet;
          };
        };
    };

    testScript = ''
      start_all()
      for machine in (router, quiet):
          machine.wait_for_unit("kea-dhcp4-server.service")

      journal = "journalctl -u kea-dhcp4-server --no-pager -o cat"

      with subtest("Kea accepts the configured severity (no LOG_BAD_SEVERITY)"):
          for machine in (router, quiet):
              machine.fail(journal + " | grep -q LOG_BAD_SEVERITY")

      with subtest("the default logs at INFO"):
          router.wait_until_succeeds(journal + " | grep -q '^INFO '")

      with subtest("logSeverity = WARN really silences INFO lines"):
          quiet.fail(journal + " | grep -q '^INFO '")
    '';
  };
}
