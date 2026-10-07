{
  lib,
  rustPlatform,
  pkg-config,
  util-linux,
  ...
}:

rustPlatform.buildRustPackage rec {
  pname = "pxe-boot-prepare";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  nativeBuildInputs = [
    pkg-config
    # `mount`/`umount` must be resolvable on $PATH during checkPhase (see
    # doCheck comment below) -- `buildInputs` does NOT reliably add a
    # package's bin/ to $PATH for rustPlatform.buildRustPackage's
    # checkPhase (confirmed empirically: with only `buildInputs`, cargo
    # test's real `mount(8)` invocation failed with "No such file or
    # directory" -- the binary wasn't found at all, not merely denied
    # permission), whereas `nativeBuildInputs` is.
    util-linux
  ];

  # `mount(8)`/`umount(8)` are genuinely invoked by one unit test
  # (status_reports_a_discovered_iso_that_fails_to_mount): it deliberately
  # exercises the FAILURE path (the build sandbox has no CAP_SYS_ADMIN,
  # so the real `mount` command fails exactly the way an unprivileged
  # production deployment attempt would) -- no elevated privileges are
  # needed to run the test suite, only `mount` actually being on $PATH.
  doCheck = true;

  meta = with lib; {
    description = "Automated PXE boot environment preparation from ISO files";
    homepage = "https://github.com/dvaerum/nixos-router-module";
    license = licenses.gpl3Plus;
    maintainers = [ ];
    platforms = platforms.linux;
    mainProgram = "pxe-boot-prepare";
  };
}
