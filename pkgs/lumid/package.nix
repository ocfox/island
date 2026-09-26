{
  stdenv,
  zig,
}:
stdenv.mkDerivation {
  pname = "lumid";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [ zig ];

  buildPhase = ''
    runHook preBuild
    export XDG_CACHE_HOME=$TMPDIR/zig-cache
    zig build-exe lumid.zig -O ReleaseFast -fstrip -femit-bin=lumid
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 lumid $out/bin/lumid
    runHook postInstall
  '';
}
