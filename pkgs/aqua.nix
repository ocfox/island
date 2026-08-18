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
    rev = "84505039854044ee4b7999b24adfdc99d773bfa2";
    hash = "sha256-Zo9sktLyo3ZLl9WI8roL4WvnFQjtGn3DNNYEzjMxgiA=";
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
