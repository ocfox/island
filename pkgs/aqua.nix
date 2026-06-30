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
    rev = "6f05383b360089f760d5abc18563dfdfaf6014d4";
    hash = "sha256-3eB18G74KEKiL8xkvKWLZ/MpvQwQ5JFidl39f1GgJyk=";
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
