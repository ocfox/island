{
  lib,
  sources,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  wrapGAppsHook4,
  gtk4,
  gtk4-layer-shell,
  libsoup_3,
  glib-networking,
  json-glib,
  sqlite,
  glib,
  gdk-pixbuf,
  wayland,
  grim,
  slurp,
  wl-clipboard,
}:

stdenv.mkDerivation {
  pname = "vertere";
  inherit (sources.vertere) version;

  src = fetchFromGitHub sources.vertere.src;

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    wrapGAppsHook4
  ];

  buildInputs = [
    gtk4
    gtk4-layer-shell
    libsoup_3
    glib-networking
    json-glib
    sqlite
    glib
    gdk-pixbuf
    wayland
  ];

  mesonBuildType = "release";
  doCheck = true;

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix PATH : ${
        lib.makeBinPath [
          grim
          slurp
          wl-clipboard
        ]
      }
    )
  '';

  meta = {
    description = "Wayland translator";
    homepage = "https://github.com/ocfox/vertere";
    license = lib.licenses.mit;
    mainProgram = "vertere";
    platforms = lib.platforms.linux;
  };
}
