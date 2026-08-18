{
  buildGoModule,
  fetchgit,
  pkg-config,
  wayland,
}:

buildGoModule {
  pname = "aqua";
  version = "0.2.0";

  src = fetchgit {
    url = "https://codeberg.org/oxc/aqua.git";
    rev = "6955a6a16ddecb591e6109ea20fd49bf647c08d2";
    hash = "sha256-/jNaY4RuNiFcjCBYkGPoBjMJ6FNFS1f3cHhh6NjZQJk=";
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
