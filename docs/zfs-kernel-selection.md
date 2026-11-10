# Newest kernel a ZFS package supports

ZFS kernel modules lag behind new Linux kernels. When a nixpkgs update brings a kernel
that your ZFS package does not support yet, the ZFS module is marked `meta.broken` and the
build fails. `lib.zfsKernel.select` picks the newest kernel the chosen ZFS package does
support, so the build keeps working and moves up on its own once ZFS catches up. It works
with any ZFS package (`pkgs.zfs`, `pkgs.zfs_unstable`, a pinned `pkgs.zfs_2_3`, ...).

Replace every placeholder written like `<this>`; see [Placeholders](#placeholders). (`<nixpkgs>` in the `nix eval` command is Nix's own search-path syntax; keep it as it is.)

## How it picks

```text
 every kernel set in pkgs.linuxKernel.packages
        |
        |  1. include    only names matching one of your patterns   (if you set any)
        |  2. exclude    drop names matching one of your patterns   (wins over include)
        |  3. -rc        drop release candidates (version contains "-rc")
        |  4. zfs        drop kernels the ZFS package does not support
        |  5. newest     highest kernel version wins
        v
   linuxPackages_X
```

- Names are `linux_6_12`, `linux_6_18`, `linux_7_2`, ... and variants such as `linux_zen`
  or `linux_xanmod`. The default considers all of them.
- If two sets have the same version, the plain mainline set (`linux_` + major + `_` + minor, like `linux_6_12`) wins.
- Removed kernels and the `linux_latest` / `linux_default` aliases are skipped.
- A kernel is "supported" when its ZFS module is not `meta.broken`. nixpkgs keeps the real
  limit private, so this is the only reliable way to ask.

## Use it in a NixOS configuration

```nix
{
  inputs.<this-flake>.url = "github:dvaerum/nixos-router-module";

  outputs = { nixpkgs, <this-flake>, ... }: {
    nixosConfigurations.<hostname> = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ config, pkgs, ... }: {
          boot.supportedFilesystems = [ "zfs" ];
          boot.zfs.package = <zfs-package>;
          boot.kernelPackages = <this-flake>.lib.zfsKernel.select {
            inherit pkgs;
            zfs = config.boot.zfs.package;   # follows the option above
          };
        })
      ];
    };
  };
}
```

Without flakes, import the file: `(import <path-to-this-repo>/lib/zfs-kernel.nix).select { pkgs = ...; zfs = ...; }`.

Arguments of `select`:

| Argument | Meaning | Default |
|----------|---------|---------|
| `pkgs` | the nixpkgs to take kernels from | required |
| `zfs` | the ZFS package to match | `pkgs.zfs` |
| `include` | list of patterns; only matching kernel sets are considered | `[ ]` (all) |
| `exclude` | list of patterns; matching kernel sets are never considered | `[ ]` |

Patterns are regular expressions that must match the whole name (`linux_6_.*` matches
`linux_6_12`; `linux_6` matches nothing).

```nix
# only the 6.x lines
include = [ "<pattern>" ];            # e.g. "linux_6_.*"

# everything except patched kernels
exclude = [ "<pattern>" "<pattern>" ];   # e.g. "linux_zen", "linux_xanmod.*"
```

## When nothing qualifies

`select` throws, listing every kernel it considered and why it was dropped. Nothing is
chosen silently, because a fallback could be a kernel you excluded or one ZFS does not
support.

Example output (the versions will differ):

```text
zfsKernel.select: no kernel qualifies for zfs-user-2.4.4. Considered:
  linux_6_12  6.12.112  not matched by `include`
  linux_7_2  7.2.10  matched by `exclude`
  linux_testing  7.3-rc6  not matched by `include`
  ...
  (36 removed or unavailable kernel sets not shown)
```

## See what it would pick

`report` takes the same arguments as `select` and lists every kernel set with its version
and status (`selected`, `ok`, `not-included`, `excluded`, `rc`, `zfs-unsupported`, `alias`,
`does-not-evaluate`):

```sh
nix eval --impure --json --expr '
  let pkgs = import <nixpkgs> { };
  in (import <path-to-this-repo>/lib/zfs-kernel.nix).report { inherit pkgs; zfs = <zfs-package>; }'
```

## ISO builder

The ISO builder (`modules/iso-builder`) uses this for its default kernel, following
`boot.zfs.package`. Narrow the choice with the options below; setting `kernelPackage`
yourself pins a kernel and bypasses the selection.

```nix
pxe-boot-iso.kernel.include = [ "<pattern>" ];
pxe-boot-iso.kernel.exclude = [ "<pattern>" ];
```

## Placeholders

| Placeholder | Meaning | What you can write | Examples |
|-------------|---------|--------------------|----------|
| `<this-flake>` | Name you give this repo as a flake input | any valid Nix identifier | `router-module` |
| `<hostname>` | Name of your NixOS configuration | any name | `my-server` |
| `<zfs-package>` | The ZFS package to match | a `pkgs.zfs*` attribute | `pkgs.zfs`, `pkgs.zfs_unstable`, `pkgs.zfs_2_3` |
| `<pattern>` | Regular expression for a kernel set name, matching the whole name | text matched with `builtins.match` | `linux_6_.*`, `linux_zen`, `linux_xanmod.*` |
| `<path-to-this-repo>` | Where this repo is checked out or fetched | a path or flake input outPath | `./nixos-router-module`, `${inputs.router-module}` |
