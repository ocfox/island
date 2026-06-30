{
  stdenv,
  fetchgit,
  pkg-config,
  wayland-scanner,
  meson,
  ninja,
  sqlite,
  json_c,
  glib,
  wayland,
  wayland-protocols,
}:

stdenv.mkDerivation {
  pname = "aqua";
  version = "0.1.0";

  src = fetchgit {
    url = "https://codeberg.org/oxc/aqua.git";
    rev = "ed24e796a289bcfbf3d61bd174695554013af8f8";
    hash = "sha256-fTYXEiHrqH9sOTQ8LlkZj5+VlSME8Uz4eC+egWv1+hM=";
  };

  nativeBuildInputs = [
    pkg-config
    wayland-scanner
    meson
    ninja
  ];

  buildInputs = [
    sqlite
    json_c
    glib
    wayland
    wayland-protocols
  ];
}
