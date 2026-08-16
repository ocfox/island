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
    rev = "82c8ffa88028ef80c6c9a6979eb34db84b45209f";
    hash = "sha256-rnZ6nFBIs01uqfCDCz8bSiuR2Cg7mp0VlUVl/rIhvVM=";
  };

  vendorHash = null;

  env.CGO_ENABLED = 0;

  meta = {
    description = "Sing-box 1.14 subscription hub and configuration assembler";
    mainProgram = "aptor";
  };
}
