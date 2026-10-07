# PXE Boot Hardening — Plan v3

## Context

After an initial 21-item PXE-boot implementation pass (shipped, verified),
a 4-agent critical review (test-coverage gaps, missing features/options,
Nix architecture, Rust architecture) plus a full `grill-me` interview
produced this 41-item plan. Executing it item-by-item with TDD discipline
and real E2E VM checkpoints (not just unit tests) — per the standing
instruction: "verify end-to-end through the real stack."

**Nothing in this work is committed yet.** `Co-Authored-By` preference is
confirmed (yes, include it) — still need explicit go-ahead before the
first commit (standing user hold on this repo this session, re-confirmed
multiple times).

## Status at a glance

| Batch | Items | Status |
|---|---|---|
| 1 | A1, A2, A4, B13, B14, B15, B17, C25, C27, C29, D37, D39, D40 | ✅ done, E2E-verified |
| 2 | A3, C26, C31, C32, C28 (partial) | ✅ done, E2E-verified |
| 3 | A7, B19 | ✅ done, E2E-verified |
| 4 | B8, B9, B10, B18 | ✅ done, E2E-verified |
| 5 | A5, A6 | ✅ done, E2E-verified |
| 6 | B11, B16 | ✅ done, package-build-verified |
| 7 | C23, C24 | ✅ done, E2E-verified |
| 8 | D41, D38, D36 | ✅ done, E2E-verified |
| 8 | D35 | 🛑 blocked — needs a design decision (see below) |
| 9 | C30 | ✅ done |
| 10 | B20 | ✅ done — CI workflow added, heavy E2E gated to manual |
| 11 | C33, C34 | ✅ done, E2E-verified |
| — | Final full-suite + both E2E tests green | ✅ done — `cargo test` 122+6 passing, `cargo clippy` clean (no new warnings), `checks.pxe-boot` and `checks.pxe-boot-secure-boot` both pass live |

Flake checks went from 10 to 14 over the course of this plan (new:
`pxe-boot-kea-client-classes`, `pxe-boot-nix-isos-wiring`,
`pxe-boot-iso-download-rate-limit`, `pxe-boot-full-disable`). Rust test
count went from 89 (session start) to 122 (119 lib + 6 bin, excludes the
3 pre-existing from before this plan).

## Open blocker: D35 design decision

**D35** (per-client/per-MAC default ISO/script) needs one of:

- **Option A — GRUB-side selection**: expose the client's MAC as a GRUB
  variable at boot time. Requires chaining iPXE in front of GRUB (a new
  boot-chain dependency this project doesn't currently have for native
  BIOS/UEFI PXE). Keeps the Nix/Rust side simple — one shared `grub.cfg`
  per interface, GRUB itself branches on MAC.
- **Option B — Nix/Rust-side selection**: generate N per-MAC-keyed Kea
  DHCP client-classes (one per pinned MAC) plus N per-MAC `grub.cfg`
  variants, served per-client. A meaningfully bigger change (touches DHCP
  config generation, the Rust GRUB-writing path, and TFTP serving), but
  no new boot-chain dependency — consistent with how per-interface
  `defaultIso`/`defaultScriptName` already work today, just keyed by MAC
  too.
- **Skip for now** — defer to a separate piece of work, move on to
  Batches 9–11 instead.

Asked the user once already (dismissed without an answer). Re-ask before
starting D35, or proceed to Batch 9 first if the user wants to come back
to it later.

## Full item list

### Section A — bug fixes / correctness

- **A1** ✅ GRUB injection escaping — percent-encoding for URL segments
  (`grub/entry.rs::url_encode_segment`) + newline/CR stripping in
  `escape_grub_string` (`grub/menu.rs`). Tests: `grub/entry.rs`,
  `grub/menu.rs`.
- **A2** ✅ TFTP race ordering — per-interface atftpd units now
  `after`/`wants` `pxe-boot-main-script.service`
  (`nixosModule/config-tftp.nix`). E2E assertion: "TFTP service is
  ordered after the file-staging service".
- **A3** ✅ mount error context — `do_mount`/`unmount` switched from
  `.status()` to `.output()`, capturing real stderr into
  `PxeBootError::MountFailed` (`iso/mount.rs`). Test:
  `status_reports_a_discovered_iso_that_fails_to_mount` (asserts on the
  `mount:`-prefixed stderr, not an exact OS-level message — the exact
  denial reason differs between an interactive shell and the Nix build
  sandbox, confirmed empirically).
- **A4** ✅ httpPort consolidation — single `testHttpPort`/`HTTP_PORT`
  binding in `tests/pxe-boot/default.nix` + `beacon.sh`, replacing 4
  independently hardcoded `1337` literals.
- **A5** ✅ real architecture detection — NixOS uses bootspec's `system`
  field (`distro/nixos.rs::architecture_from_system`, confirmed against
  nixpkgs' `bootspec.nix` source: always present, never guessed).
  Ubuntu/RHEL use filename markers (`distro/arch.rs::detect_architecture_from_file_name`,
  normalizes `amd64`→`x86_64`, `arm64`→`aarch64`).
- **A6** ✅ GRUB `$grub_cpu` conditional filtering — menu entries wrapped
  in `if [ "$grub_cpu" = "..." ]; then ... fi` when architecture is known
  (`grub/menu.rs::render_entry` + `distro/arch.rs::to_grub_cpu`).
  **Confirmed via GRUB's own `configure.ac`**: aarch64 normalizes to
  `arm64`, not `aarch64` — this exact mismatch was the flagged risk,
  verified against GRUB source before implementing.
  **Known limitation** (documented in code + E2E-confirmed): Ubuntu's
  pre-built legacy-BIOS `grub.pxe` has no `test`/`[` command compiled in
  (third-party binary, no module tree to patch) — the conditional fails
  open on BIOS clients (same pre-existing error class the file's own
  header-level `if [...]` check already had, just now 8x instead of 1x).
  UEFI (`grubx64.efi`/`grubaa64.efi`, this project's primary path) filters
  correctly.
- **A7** ✅ legacy (non-systemd) stage-1 removal — confirmed via NixOS
  Discourse that nixpkgs already defaults `boot.initrd.systemd.enable`
  to `true`. Removed `initrd.network.udhcpc.enable`,
  `initrd.extraUtilsCommands`, `initrd.postDeviceCommands`,
  `initrd.postMountCommands` legacy-only blocks from
  `modules/iso-builder/default.nix`; simplified the remaining
  systemd-stage-1-only conditionals (no longer need
  `&& config.boot.initrd.systemd.enable`); added an assertion requiring
  `boot.initrd.systemd.enable = true` whenever `enableNetworkDownload`
  is set. Test file (`tests/iso-builder-network-download-options.nix`)
  simplified to drop the now-dead `systemdStage1` parameter.

### Section B — new test coverage

- **B8** ✅ `nixIsos` test coverage — pure-eval wiring check
  (`tests/pxe-boot/default.nix::nixIsosWiringCheck`: tmpfiles `L+` entry,
  `PathChanged` inclusion, duplicate-name assertion) + real E2E coverage
  (new `nixIsoPackage` fixture mimicking a real `modules/iso-builder`
  output shape, added to the router's `pxe-boot.nixIsos` list, asserted
  discovered/mounted/served).
- **B9** ✅ `compressImage` guard — assertion in
  `modules/iso-builder/default.nix` failing loudly if
  `isoImage.compressImage = true` (nixIsos's `nix_isos_farm` hardcodes
  the uncompressed `${p}/iso/${p.name}` path). nixpkgs' own default is
  already `false`; this only fires on an explicit operator override.
- **B10** ✅ `isoDownloadRateLimit` eval check — pure-eval check
  (`isoDownloadRateLimitCheck`) confirming `"20m"` reaches nginx as
  `limit_rate 20m;` and `null` (default) emits no directive at all.
- **B11** ✅ `status` CLI argument-parsing test — `main.rs` test module
  (`Cli::try_parse_from`, `Cli::command().debug_assert()`), 6 tests.
  Required switching the "full test suite" checkpoint command from
  `cargo test --lib` to bare `cargo test` (bin-target tests are
  otherwise silently skipped).
- **B13** ✅ nginx per-interface isolation test — E2E subtest parsing
  `ss -tlnp` output, asserting the standalone-tftp-only `eth3` fixture is
  NOT in the listening-address set and the vhost never binds `0.0.0.0`.
- **B14** ✅ bash unit tests for the CI bump script —
  `check-ubuntu-netboot-release.test.sh`, 4 scenarios (bump available,
  already up to date, non-forward-bump refused, no-candidate-has-both-
  tarballs), stubbing `curl`/`nix-prefetch-url`/`nix` via a fake-bin PATH
  prepend. Wired into the real scheduled workflow.
- **B15** ✅ security-hardening regression guard — E2E subtest pinning
  `ProtectKernelModules=no` / `NoNewPrivileges=yes` on
  `pxe-boot-prepare.service`.
- **B16** ✅ `AutoinstallManager` read-only-overwrite test — 2 new tests
  proving `install_file`/`write_fresh`'s remove-then-create fix genuinely
  handles a 0444 (read-only, as `tokio::fs::copy` from `/nix/store`
  produces) destination from a prior run.
- **B17** ✅ `initrd_path` error-branch test — bundled with A1.
- **B18** ✅ full-disable state eval test — pure-eval check
  (`fullDisableCheck`): with `pxe-boot.enable = false`, confirms
  `pxe-boot-prepare.service`/`pxe-boot-main-script.service`/nginx vhost
  are fully absent, AND (the inverse) a standalone `tftpServer = true`
  interface still gets its TFTP unit regardless.
- **B19** ✅ Kea subtests extracted to pure-eval — moved two VM-dependent
  subtests ("Kea DHCP config has PXE client classes",
  "PXE options reach reserved-IP clients: PXE-E16") into
  `keaPxeClientClassesCheck`, a pure-eval check using IFD
  (`builtins.readFile` + `builtins.unsafeDiscardStringContext` on the
  rendered `kea-dhcp4.conf` derivation — `.text` is null, nixpkgs'
  `services.kea` module renders via a build step, not plain
  `builtins.toJSON`). The VM E2E test keeps the reservation fixture only
  to prove `kea-dhcp4-server.service` itself starts cleanly with it.
- **B20** ✅ CI workflow running the test suite — new
  `.github/workflows/test-suite.yml`: a `light-checks` job (pure-eval
  checks + small-VM checks + the Rust test suite via
  `pxe-boot-prepare`'s `doCheck = true`) runs automatically on every
  push/PR, cached via `nix-community/cache-nix-action` (chosen over
  `DeterminateSystems/magic-nix-cache-action` after that action's Feb 2025
  free-tier shutdown pushed users toward a paid product). The two
  genuinely heavy multi-VM checks (`pxe-boot`, `pxe-boot-secure-boot` — up
  to 30GB+ RAM across concurrent VM nodes, far beyond GitHub-hosted
  runners' 7GB) are gated behind `workflow_dispatch` (manual trigger
  only), matching the precedent already set by
  `update-pxe-boot-grub-signed.yml`'s own "run manually before merging"
  note. **Follow-up TODO**: the heavy job can't run unattended on a
  standard GitHub-hosted runner — revisit with a self-hosted runner or
  GitHub's paid larger-runner tier later.

### Section C — hardening / mechanical

- **C23** ✅ harden `pxe-boot-main-script.service` — full standard
  systemd sandboxing set (`ProtectSystem=strict` + `ReadWritePaths`
  covering every `rootFor` across `pxeBootInterfaces`, `PrivateDevices`,
  `ProtectKernelModules`, seccomp/namespace restrictions). Safe here
  (unlike `pxe-boot-prepare.service`) because this unit never calls
  `mount()` itself.
- **C24** ✅ additional `pxe-boot-prepare.service` hardening —
  `RestrictAddressFamilies=[AF_UNIX]`, `SystemCallFilter=[@system-service
  @mount]` (re-adding `@mount`, which `@system-service` excludes by
  default — this service's whole job is calling `mount()`/`umount()`),
  `RestrictNamespaces`, `LockPersonality`, `MemoryDenyWriteExecute`,
  `RestrictRealtime`, `RestrictSUIDSGID`, `RemoveIPC`. Deliberately
  excludes anything that implies a private mount namespace (same
  incompatibility `ProtectKernelModules=false` already documents).
- **C25** ✅ `validate()` per-interface `tftp_root` check — extended the
  existing global `tftp_root`-exists check to also validate each
  interface's `tftp_root` override. **Found + fixed a real bug this
  exposed**: per-interface override directories were only ever created
  by `pxe-boot-main-script.service`'s own `mkdir -p`, which runs AFTER
  `pxe-boot-prepare.service` — added `systemd.tmpfiles.rules` entries for
  every per-interface override too (mirroring the existing global-root
  fix).
- **C26** ✅ serde `deny_unknown_fields` — added to `PxeBootConfig`,
  `DhcpInterface`, `AutoinstallScript`, `HttpConfig`. Fixed a stale
  `examples/example_config.json` along the way (old
  `iso_folder_path`/two-port `http` shape).
- **C27** ✅ detector priority collision guard — removed the trait's
  default `priority()` (forces every detector, including future ones, to
  declare its own — eliminates the class of accidental-collision bug at
  compile time) + a runtime `tracing::warn!` in `register()` for
  deliberate same-priority collisions between different detectors.
- **C28** ✅ (partial) dead code removal — removed the unused
  `PxeBootError::AutoinstallNotFound` variant (confirmed zero
  construction sites anywhere, including tests). `futures` crate removal
  deliberately deferred — see C34 ordering note below.
- **C29** ✅ `GrubMenuBuilder::new()` returns `Result` instead of
  panicking on template-registration failure; removed the `Default` impl
  (can't signal failure).
- **C30** ✅ expose packages as flake outputs, fix checks/packages
  drift — the actual drift was `packages.*` holding 13 `-test` aliases
  that just re-exported `checks.*` with a `-test` suffix (no content of
  their own — `nix build .#checks.<sys>.<name>` already builds any
  check directly) while the project's two real standalone artifacts,
  `pxe-boot-prepare` and `pxe-boot-grub-signed`, weren't exposed as
  packages at all. Removed the aliases (confirmed zero references
  elsewhere in the repo), added `packages.<linux-system>.pxe-boot-prepare`
  / `pxe-boot-grub-signed` (same zero-arg `callPackage`/`import` calls
  already used by every existing call site, so no override
  reconciliation needed), gated Linux-only like the existing ISO
  outputs (both packages assume `mount`/`umount`). Verified via
  `nix build --dry-run` on x86_64-linux and `nix flake show` on
  aarch64-linux. **Separately noticed, not fixed** (out of scope for
  C30): the pinned nixpkgs (`nixpkgs-unstable`, currently resolving to
  26.11) has dropped `x86_64-darwin` support entirely, so
  `nix flake show --all-systems` / `nix flake check --all-systems`
  can't complete past that system — a flake-input/version-pin issue,
  unrelated to the checks/packages drift this item was about.
- **C31** ✅ `IsoInfo`/`BootInfo` sync helper — `IsoInfo::placeholder()` +
  `IsoInfo::apply_boot_info()` (`config/schema.rs`), replacing two
  independently-hand-copied field lists in `lib.rs` that had already
  drifted from each other (one copied `kernel_path`/`initrd_path`, the
  other didn't).
- **C32** ✅ `PxeBootError` path/operation context — new
  `PxeBootError::IoPath` variant + `IoResultExt::with_path()` extension
  trait, applied at `main.rs` (config load), `iso/mount.rs` (3 sites),
  `iso/serve_tree.rs` (5 sites). Blanket `PxeBootError::Io` kept as a
  fallback for untouched sites (`autoinstall/manager.rs`).
- **C33** ✅ DI seam for `PxeBootService` — mirrored the existing
  `DistroDetector`/`FakeDetector` pattern (`distro/detector.rs`) for the
  service's other four collaborators: new `IsoDiscovering`, `IsoMounting`,
  `ServeTreeRebuilding`, `AutoinstallPreparing` traits (`iso/discovery.rs`,
  `iso/mount.rs`, `iso/serve_tree.rs`, `autoinstall/manager.rs`), each
  implemented by its existing concrete struct with zero behavior change,
  plus a `pub` (not test-module-nested, unlike `FakeDetector`) `Fake*` for
  each so `lib.rs`'s own tests can use them. `PxeBootService`'s four fields
  became `Box<dyn Trait>`; added `new_with_dependencies(...)` as the
  fully-injectable constructor, `new(config)` now just wires up the real
  collaborators through it. Removed the unused `iso_mounter()` accessor
  (confirmed zero call sites) since its return type couldn't survive the
  `Box<dyn>` change anyway. 2 new unit tests exercise orchestration
  behavior real I/O couldn't reach unprivileged: partial mount
  success/failure across multiple ISOs in one `status()` call, and GRUB
  menu generation continuing when autoinstall preparation fails.
- **C34** ✅ selective concurrency reintroduction — kept ISO mounting
  unconditionally sequential (sidesteps relying on the old, uncorroborated
  "TOCTOU race reproduced" comment either way — the design simply never
  takes the risk). Reintroduced `futures::future::join_all` for the three
  stages that don't touch mount-related shared state: `ServeTree::rebuild`'s
  per-ISO symlink loop, `AutoinstallManager::prepare`'s per-(iso, script)
  writes (flattened from a nested loop), and `PxeBootService::prepare`'s
  per-interface GRUB menu generation. `futures` goes from unused back to
  used, so C28's deferred "remove `futures`" half is moot. New unit test
  (`autoinstall::manager::tests::one_scripts_failure_does_not_block_another_scripts_write`)
  proves a real behavior change from the old sequential code: previously a
  failing script's `?` would short-circuit and never attempt a later
  script in the same loop; now every write is attempted independently.
  Full E2E VM check (`checks.x86_64-linux.pxe-boot`, including the 4-ISO
  `findiso` fixture that originally triggered the mount race) passed
  clean: "test script finished in 156.41s", no real build errors.

### Section D — new features

- **D35** 🛑 blocked — per-client (per-MAC) default ISO/script. See
  "Open blocker" above.
- **D36** ✅ `findiso=` download resume — `wget --continue` added;
  idempotent tmpfs-mount guard (`grep -q ' /run/findiso ' /proc/mounts`
  before mounting) prevents a second script invocation from stacking a
  fresh tmpfs over a partial download, which would silently defeat
  `--continue`. 2 new pure-eval assertions in
  `tests/iso-builder-network-download-options.nix` — note: the first
  version of the `--continue` check was accidentally vacuous (matched
  the explanatory comment's prose, not just the real flag); caught by
  actually running the negative-case test, fixed to anchor on the
  flag + line-continuation backslash.
- **D37** ✅ Secure Boot shim override option —
  `my.router.pxe-boot.shimPackage` (`types.package`, defaults to this
  project's own `pxe-boot-grub-signed`), consumed in
  `config-tftp.nix`'s `signed-grub` binding.
- **D38** ✅ concurrent-`prepare()` lock — `fs4` crate (tokio-async
  `try_lock`), exclusive non-blocking lock on
  `<runtime_root>/.prepare.lock`, held for `prepare()`'s whole scope.
  Fails fast (does not block) when another run already holds it.
- **D39** ✅ threat-model docs — new "Security Model" section in
  `packages/pxe-boot-prepare/README.md`: LAN-only trust assumption,
  Secure Boot covers the boot chain only (not post-boot ISO/script
  fetch), why TLS was declined on the merits (circular trust-bootstrap
  problem for a pre-OS PXE service).
- **D40** ✅ softened aarch64 overclaims — `modules/iso-builder/README.md`
  feature-list entry no longer claims equal-footing "cross-platform"
  support; "Architecture Notes" section strengthened to explicitly flag
  that the aarch64 Secure Boot path ships a binary but has no E2E
  coverage.
- **D41** ✅ loud unsupported-ISO signal — ISOs that fail distro
  detection/extraction now get a non-bootable, clearly-labeled GRUB
  placeholder entry (`<filename> (unsupported)`, echoes the real reason,
  `read` + `configfile` to return to the menu) instead of only a
  `tracing::warn!` line nobody browsing the boot menu would ever see.
  `GrubMenuBuilder::add_placeholder_entry` + `render_placeholder`;
  threaded a new `failed_isos: Vec<(String, String)>` through
  `prepare()` → `generate_grub_menu`.

### Explicitly declined / deferred (not part of this plan)

New distro detectors beyond what exists, metrics/observability, TLS,
IPv6/DHCPv6, `options.nix` naming/namespace cleanup (left as documented
warts), an aarch64 Secure Boot E2E test (x86_64 coverage judged
sufficient).

## Toolchain notes (for continuing this work)

- Rust iteration: `nix shell nixpkgs#cargo nixpkgs#rustc
  nixpkgs#pkg-config nixpkgs#util-linux nixpkgs#gcc nixpkgs#binutils
  nixpkgs#mold nixpkgs#sccache -c cargo test` (bare `cargo test`, not
  `--lib` — see B11). Global `~/.cargo/config.toml` forces `mold` +
  `sccache`, hence the extra packages.
- **New files must be `git add`-ed (not committed) before `nix build`
  can see them** — bit this session at least twice (`distro/arch.rs`,
  `check-ubuntu-netboot-release.test.sh`). `nix build` only sees
  git-tracked files from a dirty working tree.
- Full E2E VM test: `nix build --no-link --print-out-paths
  .#checks.x86_64-linux.pxe-boot -L`, ~2.5–3 min per run. Run detached
  (`setsid nohup ... &` + `disown`) since the bash tool's own 120s
  timeout kills the foreground wait, not the underlying process, if you
  don't detach it. Poll via `tail -N <logfile>`.
- A recurring "error:" false-positive in E2E logs: GRUB client-side boot
  chatter (`net/tftp.c:tftp_receive:254:File not found.`,
  `script/function.c:grub_script_function_find:119:can't find command`
  — the latter being A6's documented legacy-BIOS `test`-module gap) is
  normal, not a test failure. Check for the real pass/fail signal (output
  store path printed, `test script finished in NNs`, no `error: builder
  failed`), not a bare `grep -c "error:"` count.
- Pure-eval Nix checks (`pkgs.runCommand` + `throw` on failure) are much
  cheaper than the VM test for anything that's really just module-
  evaluation logic — but **verify them with a genuine negative-case run**
  before trusting them; this session's own checks were wrong on the first
  attempt at least 3 times (an always-force-evaluated `throw` body that
  crashed on unrelated nixpkgs module internals, a `--continue` check
  that matched its own explanatory comment instead of the real flag, an
  `fs2`-style lock test that needed the file content, not just existence).

## Next step

Every item except **D35** is done and E2E-verified, including the final
full-suite + both-E2E-green checkpoint. D35 (per-client/per-MAC default
ISO/script) is still an open design conversation with the user — the only
remaining work on this plan. Nothing is committed/pushed yet (explicit
user hold on this repo this session).
