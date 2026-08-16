{
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule {
  pname = "aptor";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "ocfox";
    repo = "aptor";
    rev = "91135478e82e18fb330b562505586a29136f52e0";
    hash = "sha256-bf9oKCLAB53Ieh8jB/HAfLoao7sNIZvlts6EU5Y8dCs=";
  };

  vendorHash = null;

  env.CGO_ENABLED = 0;

  meta = {
    description = "Sing-box 1.14 subscription hub and configuration assembler";
    mainProgram = "aptor";
  };
}
