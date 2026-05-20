{
  lib,
  fetchzip,
  stdenvNoCC,
  win2xcur,
}:

let
  version = "1";
  src = fetchzip {
    name = "teto-cursor";
    url = "https://s3.s4r.in/teto-cursor.zip";
    hash = "sha256-un5FsVtjWORScQRlj8rrhYdtUjR3o7UzliXfN5ML8rw=";
    stripRoot = false;
  };
in
stdenvNoCC.mkDerivation {
  pname = "teto-cursor";
  inherit version src;

  nativeBuildInputs = [ win2xcur ];

  buildPhase = ''
    cd "teto 1"
    mkdir output
    win2xcur -o output *.ani *.cur
  '';

  installPhase = ''
    mkdir -p $out/share/icons/teto-cursor/cursors
    cp -r output/. $out/share/icons/teto-cursor/cursors/
    cat > $out/share/icons/teto-cursor/cursor.theme <<EOF
    [Icon Theme]
    Name=teto-cursor
    EOF
    cat > $out/share/icons/teto-cursor/index.theme <<EOF
    [Icon Theme]
    Name=teto-cursor
    Comment=Teto cursor theme
    EOF
  '';

  meta = {
    description = "Teto cursor theme";
    license = lib.licenses.unfree;
    platforms = lib.platforms.linux;
  };
}
