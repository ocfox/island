{
  buildGoModule,
  fetchgit,
  pkg-config,
  wayland,
}:

buildGoModule {
  pname = "aqua";
  version = "0-unstable-2026-08-18";

  src = fetchgit {
    url = "https://codeberg.org/oxc/aqua.git";
    rev = "da28193bf8bd4ad6e0c517e8ebc38332300b57ac";
    hash = "sha256-WAwJ5pYz3ym1gv5zMU8+HgtFhG8wyyw7Hcy+Jxxnq54=";
  };

  vendorHash = "sha256-rSfdTqix9aDZihF20ahPAqPcSXpsTasEEjoD3ADtDeo=";

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    wayland
  ];

  meta = {
    description = "Lightweight desktop activity tracking daemon";
    mainProgram = "aqua";
  };
}
