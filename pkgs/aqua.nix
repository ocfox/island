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
    rev = "1e99073c9fa84c2cc629314a374a60d118307dff";
    hash = "sha256-2ZxakY9AF5FJlKUtzaGMf0+DY7AMdiyWDF/M04ToVeI=";
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
