{ lib
, rustPlatform
, pkg-config
, util-linux
, ...
}:

rustPlatform.buildRustPackage rec {
  pname = "pxe-boot-prepare";
  version = "0.1.0";

  src = ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    util-linux # For mount/umount
  ];

  # Tests require mounting, which needs privileges
  doCheck = false;

  meta = with lib; {
    description = "Automated PXE boot environment preparation from ISO files";
    homepage = "https://github.com/dvaerum/nixos-router-module";
    license = licenses.gpl3Plus;
    maintainers = [];
    platforms = platforms.linux;
    mainProgram = "pxe-boot-prepare";
  };
}
