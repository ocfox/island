{
  callPackage,
  ocamlPackages,
}:

ocamlPackages.buildDunePackage {
  pname = "aqua-server";
  version = "unstable-2026-06-26";

  src = callPackage ./aqua-source.nix { };

  propagatedBuildInputs = with ocamlPackages; [
    eio
    eio_main
    caqti
    caqti-driver-postgresql
    httpun
    httpun-eio
    ptime
    ocaml_sqlite3
    uri
    yojson
  ];

  buildPhase = "dune build bin/server/main.exe";

  installPhase = ''
    install -Dm755 _build/default/bin/server/main.exe $out/bin/aqua-server
    install -Dm444 db/migrations/001_initial.sql $out/share/aqua/migrations/001_initial.sql
  '';
}
