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
    rev = "2d8b006075ca027ce30f2d9ac0e65610c5f739d4";
    hash = "sha256-SV3u6jh0Whd22oJNKHHp/VoUa0zwoDoU66bA8WHriPw=";
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
