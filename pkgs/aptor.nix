{
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule {
  pname = "aptor";
  version = "0-unstable-2026-08-18";

  src = fetchFromGitHub {
    owner = "ocfox";
    repo = "aptor";
    rev = "abc7cce9cf576a13175652b2b388c6b1d8fa8c3b";
    hash = "sha256-rLhME+cdxRCIqegmF/v1E7dO8Q3XWWb9csGrhsMuf48=";
  };

  vendorHash = null;

  env.CGO_ENABLED = 0;

  meta = {
    description = "Sing-box 1.14 subscription hub and configuration assembler";
    mainProgram = "aptor";
  };
}
