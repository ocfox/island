{
  stdenv,
  odin,
}:
stdenv.mkDerivation {
  pname = "m220";
  version = "0.2.0";
  src = ./.;

  nativeBuildInputs = [ odin ];

  buildPhase = ''
    runHook preBuild
    odin build m220.odin -file -out:m220 -o:size
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 m220 $out/bin/m220
    runHook postInstall
  '';
}
