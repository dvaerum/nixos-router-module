# Pick the newest Linux kernel package set that a given ZFS package supports.
#
#   zfsKernel.select  { pkgs; zfs ? pkgs.zfs; include ? [ ]; exclude ? [ ]; }  -> linuxPackages set
#   zfsKernel.report  (same arguments)  -> [ { name; version; status; } ]
#   zfsKernel.explain (same arguments)  -> the text of the "nothing qualifies" error
#
# See docs/zfs-kernel-selection.md for the rules and examples.
#
# nixpkgs gives no public way to ask a ZFS package for its newest supported
# kernel (the limit is private to its generic.nix), so "supported" is decided by
# `meta.broken` of the ZFS kernel module built for each candidate kernel.
let
  # Names of kernel sets that point at another set; counting them would let a
  # name-based `exclude` of the real set be bypassed through its alias.
  aliasNames = [
    "linux_latest"
    "linux_default"
  ];

  # `linux_<major>_<minor>`: the plain upstream sets win a tie on version.
  isPlainMainline = name: builtins.match "linux_[0-9]+_[0-9]+" name != null;

  statusText =
    zfsName: status:
    {
      selected = "selected";
      ok = "supported, but an even newer kernel was selected";
      not-included = "not matched by `include`";
      excluded = "matched by `exclude`";
      rc = "release candidate (-rc)";
      zfs-unsupported = "${zfsName} does not support this kernel";
      alias = "alias of another kernel set";
      does-not-evaluate = "does not evaluate (removed or broken alias)";
    }
    .${status};

  report =
    {
      pkgs,
      zfs ? pkgs.zfs,
      include ? [ ],
      exclude ? [ ],
    }:
    let
      inherit (pkgs) lib;
      sets = pkgs.linuxKernel.packages;
      matchesAny = patterns: name: lib.any (p: builtins.match p name != null) patterns;

      # Force a set inside tryEval: removed kernels are `throw` aliases, and
      # non-set entries (recurseForDerivations) must be skipped.
      probe =
        name:
        let
          set = builtins.tryEval (
            let
              v = sets.${name};
            in
            if builtins.isAttrs v then v else throw "not a kernel set"
          );
          version = if set.success then builtins.tryEval set.value.kernel.version else set;
          supported =
            set.success
            && set.value ? ${zfs.kernelModuleAttribute}
            && (
              let
                r = builtins.tryEval (!(set.value.${zfs.kernelModuleAttribute}.meta.broken or false));
              in
              r.success && r.value
            );
          status =
            if !set.success || !version.success then
              "does-not-evaluate"
            else if lib.elem name aliasNames then
              "alias"
            else if include != [ ] && !(matchesAny include name) then
              "not-included"
            else if matchesAny exclude name then
              "excluded"
            else if lib.hasInfix "-rc" version.value then
              "rc"
            else if !supported then
              "zfs-unsupported"
            else
              "ok";
        in
        {
          inherit name status;
          version = if version.success then version.value else null;
        };

      probed = map probe (builtins.filter (n: lib.hasPrefix "linux_" n) (builtins.attrNames sets));

      better =
        a: b:
        let
          c = builtins.compareVersions a.version b.version;
        in
        if c != 0 then
          c > 0
        else if isPlainMainline a.name != isPlainMainline b.name then
          isPlainMainline a.name
        else
          a.name < b.name;

      winner = lib.findFirst (_: true) null (
        builtins.sort better (builtins.filter (e: e.status == "ok") probed)
      );
    in
    map (
      e: if winner != null && e.name == winner.name then e // { status = "selected"; } else e
    ) probed;

  explain =
    args@{
      pkgs,
      zfs ? pkgs.zfs,
      ...
    }:
    let
      inherit (pkgs) lib;
      zfsName = zfs.name or "the ZFS package";
      all = report args;
      # Removed and hardened kernel sets that can never qualify would drown the
      # useful lines; show only a count of them.
      shown = builtins.filter (e: e.status != "does-not-evaluate") all;
      hidden = builtins.length all - builtins.length shown;
      lines = map (e: "  ${e.name}  ${e.version}  ${statusText zfsName e.status}") shown;
    in
    "zfsKernel.select: no kernel qualifies for ${zfsName}. Considered:\n"
    + builtins.concatStringsSep "\n" lines
    + lib.optionalString (
      hidden > 0
    ) "\n  (${toString hidden} removed or unavailable kernel sets not shown)";
in
{
  inherit report explain;

  select =
    {
      pkgs,
      zfs ? pkgs.zfs,
      include ? [ ],
      exclude ? [ ],
    }:
    let
      args = {
        inherit
          pkgs
          zfs
          include
          exclude
          ;
      };
      chosen = pkgs.lib.findFirst (e: e.status == "selected") null (report args);
    in
    if chosen == null then throw (explain args) else pkgs.linuxKernel.packages.${chosen.name};
}
