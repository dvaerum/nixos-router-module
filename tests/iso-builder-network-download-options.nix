{
  pkgs ? import <nixpkgs> { },
}:
###########################################################################
# Pure-eval check (no VM, no build): `networkDownloadTmpfsSize` and
# `networkDownloadStallTimeoutSec` must actually reach the rendered
# `boot.initrd.systemd.services.findiso-download.script`. This only
# checks that OUR module's string interpolation is wired correctly; it
# is not a substitute for the real findiso= download E2E test (that one
# lives in tests/pxe-boot/default.nix).
###########################################################################
let
  customTmpfsSize = "7G";
  customStallTimeout = 123;

  evaluated =
    (pkgs.nixos (
      { lib, ... }:
      {
        imports = [ ../modules/iso-builder ];
        pxe-boot-iso.enable = true;
        pxe-boot-iso.enableNetworkDownload = true;
        pxe-boot-iso.networkDownloadTmpfsSize = customTmpfsSize;
        pxe-boot-iso.networkDownloadStallTimeoutSec = customStallTimeout;
      }
    )).config;

  systemdScript = evaluated.boot.initrd.systemd.services.findiso-download.script;

  checks = [
    {
      name = "systemd stage-1 tmpfs size";
      ok = pkgs.lib.hasInfix "size=${customTmpfsSize}" systemdScript;
    }
    {
      name = "systemd stage-1 stall timeout";
      ok = pkgs.lib.hasInfix "--read-timeout=${toString customStallTimeout}" systemdScript;
    }
    {
      # D36: resumes a stalled/retried download instead of restarting
      # from byte 0 -- wget's own default retry count (20) already
      # retries on a --read-timeout kill, this just makes those retries
      # actually cheap. Checks for the flag followed by a line-
      # continuation backslash specifically (not just the bare substring
      # "--continue", which the explanatory comment ABOVE the real wget
      # invocation also contains -- confirmed this exact check is
      # otherwise vacuous: it still "passed" with the real flag removed,
      # caught only by actually trying that negative case).
      name = "wget invocation includes --continue (D36 resume support)";
      ok = pkgs.lib.hasInfix "--continue \\" systemdScript;
    }
    {
      # D36: idempotent tmpfs mount guard -- a second script invocation
      # must not stack a fresh tmpfs over the first, which would shadow
      # (hide) whatever partial download --continue needs to resume.
      name = "tmpfs mount is guarded against being mounted twice";
      ok = pkgs.lib.hasInfix "grep -q ' /run/findiso '" systemdScript;
    }
  ];

  failures = builtins.filter (c: !c.ok) checks;
in
pkgs.runCommand "iso-builder-network-download-options-check" { } (
  if failures == [ ] then
    "touch $out"
  else
    throw ''
      networkDownloadTmpfsSize/networkDownloadStallTimeoutSec did not reach
      the rendered initrd script as expected: ${builtins.toJSON (map (f: f.name) failures)}

      systemd stage-1 script:
      ${systemdScript}
    ''
)
