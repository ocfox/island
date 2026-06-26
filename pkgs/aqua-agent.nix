{
  fetchgit,
  pkg-config,
  wayland-scanner,
  wayland,
  wayland-protocols,
  glib,
  ocamlPackages,
}:

ocamlPackages.buildDunePackage {
  pname = "aqua-agent";
  version = "unstable-2026-06-26";

  src = fetchgit {
    url = "https://codeberg.org/oxc/aqua.git";
    rev = "33a81bc4f8264b330ecc0b8d41ade1f72e4d5a64";
    hash = "sha256-eazg4B6NDPtOxqfTHR6bL52KdtjqnffP3Aj3U1bznLY=";
  };

  nativeBuildInputs = [
    pkg-config
    wayland-scanner
  ];

  buildInputs = [
    glib
    wayland
    wayland-protocols
  ];

  propagatedBuildInputs = with ocamlPackages; [
    base64
    digestif
    eio
    eio_main
    mirage-crypto-rng
    ptime
    ocaml_sqlite3
    tls-eio
    yojson
  ];

  buildPhase = "dune build bin/agent/main.exe";

  installPhase = ''
    install -Dm755 _build/default/bin/agent/main.exe $out/bin/aqua-agent
  '';
}
