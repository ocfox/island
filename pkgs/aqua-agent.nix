{
  callPackage,
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

  src = callPackage ./aqua-source.nix { };

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
    eio
    eio_main
    mirage-crypto-rng
    ptime
    ocaml_sqlite3
    tls-eio
    uri
    yojson
  ];

  buildPhase = "dune build bin/agent/main.exe";

  installPhase = ''
    install -Dm755 _build/default/bin/agent/main.exe $out/bin/aqua-agent
  '';
}
