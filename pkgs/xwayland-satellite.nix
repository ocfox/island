{
  lib,
  fetchFromGitHub,
  installShellFiles,
  libxcb,
  makeBinaryWrapper,
  pkg-config,
  rustPlatform,
  libxcb-cursor,
  xwayland,
}:

rustPlatform.buildRustPackage {
  pname = "xwayland-satellite";
  version = "0.8.1-unstable-2026-05-30";

  src = fetchFromGitHub {
    owner = "Supreeeme";
    repo = "xwayland-satellite";
    rev = "8575d0ef55d70f9b4c46b6bffb3accf912217e1e";
    hash = "sha256-28696iIw8uE0ZUyFTtzhEM8xMh85clCYypMxkvUi+sc=";
  };

  postPatch = ''
    substituteInPlace resources/xwayland-satellite.service \
      --replace-fail '/usr/local/bin' "$out/bin"
  '';

  cargoHash = "sha256-jbEihJYcOwFeDiMYlOtaS8GlunvSze80iWahDj1qDrs=";

  nativeBuildInputs = [
    installShellFiles
    makeBinaryWrapper
    pkg-config
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    libxcb
    libxcb-cursor
  ];

  buildNoDefaultFeatures = true;
  buildFeatures = [ "systemd" ];

  outputs = [
    "out"
    "man"
  ];

  # All integration tests require a running display server
  doCheck = false;

  postInstall = ''
    installManPage --name xwayland-satellite.1 xwayland-satellite.man
    install -Dm0644 resources/xwayland-satellite.service -t $out/lib/systemd/user
  '';

  postFixup = ''
    wrapProgram $out/bin/xwayland-satellite \
      --prefix PATH : "${lib.makeBinPath [ xwayland ]}"
  '';

  meta.mainProgram = "xwayland-satellite";
}
