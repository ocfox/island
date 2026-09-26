{
  lib,
  rustPlatform,
  pkg-config,
  wayland,
}:

rustPlatform.buildRustPackage {
  pname = "milk";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    wayland
  ];

  postInstall = ''
    ln -s milk $out/bin/grim
  '';

  meta = {
    mainProgram = "milk";
  };
}
