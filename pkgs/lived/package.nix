{
  lib,
  buildGoModule,
  makeWrapper,
  playerctl,
  libnotify,
}:

buildGoModule {
  pname = "lived";
  version = "0.1.0";

  src = ./.;

  vendorHash = null;

  env.CGO_ENABLED = 0;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/lived \
      --prefix PATH : ${
        lib.makeBinPath [
          playerctl
          libnotify
        ]
      }
  '';

  meta = {
    description = "Personal desktop presence, Spotify MPRIS, and Wayland idle exporter daemon";
    mainProgram = "lived";
  };
}
