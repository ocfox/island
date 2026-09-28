{
  lib,
  sources,
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
  inherit (sources.xwayland-satellite) version cargoHash;

  src = fetchFromGitHub sources.xwayland-satellite.src;

  postPatch = ''
    substituteInPlace resources/xwayland-satellite.service \
      --replace-fail '/usr/local/bin' "$out/bin"
  '';

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
