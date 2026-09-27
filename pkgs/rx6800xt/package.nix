{
  stdenv,
  zig,
}:
stdenv.mkDerivation {
  pname = "rx6800xt";
  version = "1.0.0";
  src = ./.;

  nativeBuildInputs = [ zig ];

  buildPhase = ''
    runHook preBuild
    export XDG_CACHE_HOME=$TMPDIR/zig-cache
    zig build-exe rx6800xt.zig -O ReleaseFast -fstrip -femit-bin=rx6800xt
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 rx6800xt $out/bin/rx6800xt
    install -Dm644 60-rx6800xt.rules $out/lib/udev/rules.d/60-rx6800xt.rules
    runHook postInstall
  '';
}
