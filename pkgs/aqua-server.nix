{
  fetchgit,
  ocamlPackages,
}:

ocamlPackages.buildDunePackage {
  pname = "aqua-server";
  version = "unstable-2026-06-26";

  src = fetchgit {
    url = "https://codeberg.org/oxc/aqua.git";
    rev = "bd7fc5026eb3ed24c9258f3bbf4187c2d32e1a1b";
    hash = "sha256-Kw0uQ8nkRgKGObha6n3cu0gBuXCnX7M1865Ksib6daA=";
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
