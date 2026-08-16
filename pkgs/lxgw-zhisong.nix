{
  lib,
  stdenv,
  fetchurl,
}:

stdenv.mkDerivation rec {
  pname = "lxgw-zhisong";
  version = "1.001";

  src = fetchurl {
    url = "https://github.com/lxgw/LxgwZhiSong/releases/download/v${version}/LXGWZhiSongMN.ttf";
    hash = "sha256-BVcIxEl6D0Z44Yp7uTOlE4nzd+KvPlKJYAKjef3Sh0U=";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    install -Dm444 "$src" "$out/share/fonts/truetype/LXGWZhiSongMN.ttf"

    runHook postInstall
  '';
}
