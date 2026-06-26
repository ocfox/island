{
  fetchgit,
  ocamlPackages,
}:

ocamlPackages.buildDunePackage {
  pname = "aqua-server";
  version = "unstable-2026-06-26";

  src = fetchgit {
    url = "https://codeberg.org/oxc/aqua.git";
    rev = "20a18289b29f7ca28ecb3a9b00b00af0b4e4841f";
    hash = "sha256-45/oyghh8lHEOneZ3r/8d+RapkxRWa30RNDKmkUalt0=";
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
