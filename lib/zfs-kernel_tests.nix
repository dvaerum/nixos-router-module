{
  pkgs ? import <nixpkgs> { },
}:
let
  inherit (pkgs) lib;
  zfsKernel = import ./zfs-kernel.nix;

  # A fake kernel set. Each fake ZFS package reads its own `<attr>.meta.broken`,
  # computed from a maximum supported kernel the same way nixpkgs does it.
  mkKp = name: version: {
    _name = name;
    kernel = { inherit version; };
    zfs_stable.meta.broken = !(lib.versionAtLeast "7.2" (lib.versions.majorMinor version));
    zfs_unstable.meta.broken = !(lib.versionAtLeast "7.3" (lib.versions.majorMinor version));
    zfs_any.meta.broken = false;
  };

  fakePkgs = {
    inherit lib;
    linuxKernel.packages = {
      linux_6_12 = mkKp "linux_6_12" "6.12.111";
      linux_6_18 = mkKp "linux_6_18" "6.18.54";
      linux_7_2 = mkKp "linux_7_2" "7.2.8";
      linux_7_3 = mkKp "linux_7_3" "7.3.1";
      linux_testing = mkKp "linux_testing" "7.4-rc1";
      linux_zen = mkKp "linux_zen" "7.2.8";
      linux_latest = mkKp "linux_latest" "7.2.8";
      linux_6_1 = throw "removed kernel";
      recurseForDerivations = true;
    };
  };

  zfsStable = {
    name = "zfs-stable-fake";
    kernelModuleAttribute = "zfs_stable";
  };
  zfsUnstable = {
    name = "zfs-unstable-fake";
    kernelModuleAttribute = "zfs_unstable";
  };
  zfsAny = {
    name = "zfs-any-fake";
    kernelModuleAttribute = "zfs_any";
  };

  pick =
    args:
    (zfsKernel.select (
      {
        pkgs = fakePkgs;
        zfs = zfsStable;
      }
      // args
    ))._name;
  statusOf =
    args: name:
    (lib.findFirst (e: e.name == name) null (
      zfsKernel.report (
        {
          pkgs = fakePkgs;
          zfs = zfsStable;
        }
        // args
      )
    )).status;
in
lib.runTests {
  test_stable_zfs_skips_unsupported_newer_kernel = {
    expr = pick { };
    expected = "linux_7_2";
  };

  test_unstable_zfs_accepts_the_newer_kernel = {
    expr = pick { zfs = zfsUnstable; };
    expected = "linux_7_3";
  };

  test_rc_kernel_is_never_picked_even_if_zfs_would_accept_it = {
    expr = pick { zfs = zfsAny; };
    expected = "linux_7_3";
  };

  test_same_version_prefers_plain_mainline_over_variant_and_alias = {
    expr = pick { };
    expected = "linux_7_2";
  };

  test_exclude_regex_removes_a_family_and_next_best_wins = {
    expr = pick {
      exclude = [
        "linux_7_.*"
        "linux_zen"
      ];
    };
    expected = "linux_6_18";
  };

  test_exclude_does_not_remove_variants_it_does_not_match = {
    expr = pick { exclude = [ "linux_7_.*" ]; };
    expected = "linux_zen";
  };

  test_include_restricts_to_matching_names = {
    expr = pick { include = [ "linux_6_.*" ]; };
    expected = "linux_6_18";
  };

  test_exclude_wins_over_include = {
    expr = pick {
      include = [ "linux_6_.*" ];
      exclude = [ "linux_6_18" ];
    };
    expected = "linux_6_12";
  };

  test_patterns_are_anchored = {
    # "linux_6" is a prefix of linux_6_12 / linux_6_18 but must not match them.
    expr =
      (builtins.tryEval (pick {
        include = [ "linux_6" ];
      })).success;
    expected = false;
  };

  test_nothing_qualifies_throws = {
    expr =
      (builtins.tryEval (
        zfsKernel.select {
          pkgs = fakePkgs;
          zfs = zfsStable;
          exclude = [ ".*" ];
        }
      )).success;
    expected = false;
  };

  test_error_message_names_every_reason = {
    expr =
      let
        msg = zfsKernel.explain {
          pkgs = fakePkgs;
          zfs = zfsStable;
          exclude = [ "linux_7_.*" ];
          include = [ "linux_[67]_.*" ];
        };
      in
      map (s: lib.hasInfix s msg) [
        "linux_7_3"
        "matched by `exclude`"
        "not matched by `include`"
        "zfs-stable-fake"
        "(1 removed or unavailable kernel sets not shown)"
      ];
    expected = [
      true
      true
      true
      true
      true
    ];
  };

  test_error_message_does_not_list_removed_kernel_sets = {
    expr = lib.hasInfix "linux_6_1  " (
      zfsKernel.explain {
        pkgs = fakePkgs;
        zfs = zfsStable;
      }
    );
    expected = false;
  };

  test_report_statuses = {
    expr = map (statusOf { }) [
      "linux_6_12"
      "linux_7_2"
      "linux_7_3"
      "linux_testing"
      "linux_zen"
      "linux_latest"
      "linux_6_1"
    ];
    expected = [
      "ok"
      "selected"
      "zfs-unsupported"
      "rc"
      "ok"
      "alias"
      "does-not-evaluate"
    ];
  };

  test_non_kernel_entries_are_not_reported = {
    expr = map (e: e.name) (
      zfsKernel.report {
        pkgs = fakePkgs;
        zfs = zfsStable;
      }
    );
    expected = [
      "linux_6_1"
      "linux_6_12"
      "linux_6_18"
      "linux_7_2"
      "linux_7_3"
      "linux_latest"
      "linux_testing"
      "linux_zen"
    ];
  };
}
