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
    rev = "1dcde7b6c02c772defbf88f822710c7318388f79";
    hash = "sha256-/bWypbK0cvw5+MOybw1b5FT+yoTqJcQQ+0Ig2GoEdtw=";
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
