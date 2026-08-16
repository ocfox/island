{
  lib,
  stdenv,
  fetchurl,
}:

stdenv.mkDerivation rec {
  pname = "lxgw-neoxihei";
  version = "1.304";

  src = fetchurl {
    url = "https://github.com/lxgw/LxgwNeoXiHei/releases/download/v${version}/LXGWNeoXiHeiPlus.ttf";
    hash = "sha256-vYjWfIxw2VyxIUj7e31qEjlWIyTsh0NqOAbqBB9Uq4I=";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    install -Dm444 "$src" "$out/share/fonts/truetype/LXGWNeoXiHeiPlus.ttf"

    runHook postInstall
  '';
}
