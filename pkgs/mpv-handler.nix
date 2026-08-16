{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage rec {
  pname = "mpv-handler";
  version = "0.4.2";

  src = fetchFromGitHub {
    owner = "akiirui";
    repo = "mpv-handler";
    rev = "v${version}";
    hash = "sha256-QoctjneJA7CdXqGm0ylAh9w6611vv2PD1fzS0exag5A=";
  };

  cargoHash = "sha256-gKDkDLTLzC53obDd7pORsqP6DhORTbx6tvQ4jq61znQ=";

  postInstall = ''
    install -Dm444 -t $out/share/applications share/linux/mpv-handler.desktop
  '';

  meta = {
    description = "A protocol handler for mpv. Use mpv and yt-dlp to play video and music from the websites";
    homepage = "https://github.com/akiirui/mpv-handler";
    license = lib.licenses.mit;
    mainProgram = "mpv-handler";
  };
}
