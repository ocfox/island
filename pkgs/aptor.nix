{
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule {
  pname = "aptor";
  version = "0-unstable-2026-08-16";

  src = fetchFromGitHub {
    owner = "ocfox";
    repo = "aptor";
    rev = "a6977098344bbbada01b3a3e2d7f0e6d4334b88d";
    hash = "sha256-KQTKfPkYMxVX7E2RDIAQ4wNKYD4FdZlgoOFfcvA545g=";
  };

  vendorHash = null;

  env.CGO_ENABLED = 0;

  meta = {
    description = "Sing-box 1.14 subscription hub and configuration assembler";
    mainProgram = "aptor";
  };
}
