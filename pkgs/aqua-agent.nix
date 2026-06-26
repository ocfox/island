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
    rev = "20a18289b29f7ca28ecb3a9b00b00af0b4e4841f";
    hash = "sha256-45/oyghh8lHEOneZ3r/8d+RapkxRWa30RNDKmkUalt0=";
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
