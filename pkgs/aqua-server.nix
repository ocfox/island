{
  fetchgit,
  ocamlPackages,
}:

ocamlPackages.buildDunePackage {
  pname = "aqua-server";
  version = "unstable-2026-06-26";

  src = fetchgit {
    url = "https://codeberg.org/oxc/aqua.git";
    rev = "83551cca7dc9115595af09cf87eb41a8d0d9664a";
    hash = "sha256-rc96LVyk0eUQaLxiXhvuQZOaYQ4WfNQOaqGGX9KQOKo=";
  };

  propagatedBuildInputs = with ocamlPackages; [
    base64
    digestif
    eio
    eio_main
    ptime
    ocaml_sqlite3
    yojson
  ];

  buildPhase = "dune build bin/server/main.exe";

  installPhase = ''
    install -Dm755 _build/default/bin/server/main.exe $out/bin/aqua-server
  '';
}
