{
  lib,
  sources,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  wrapGAppsHook4,
  gtk4,
  gtk4-layer-shell,
  glib,
  cairo,
  pango,
  gdk-pixbuf,
  graphene,
  wayland,
  grim,
  slurp,
  wl-clipboard,
}:

rustPlatform.buildRustPackage {
  pname = "vertere";
  inherit (sources.vertere) version cargoHash;

  src = fetchFromGitHub sources.vertere.src;

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook4
  ];

  buildInputs = [
    gtk4
    gtk4-layer-shell
    glib
    cairo
    pango
    gdk-pixbuf
    graphene
    wayland
  ];

  postInstall = ''
    mkdir -p $out/share
    cp -r data/applications data/icons -t $out/share/
  '';

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
