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
    rev = "188cbff4e20220befd5ea672b168fb4f5925a05f";
    hash = "sha256-CuuUCh6bySHrpqSyGkpqC0XYcULGflwy5b5q7SmCPPo=";
  };

  vendorHash = null;

  env.CGO_ENABLED = 0;

  meta = {
    description = "Sing-box 1.14 subscription hub and configuration assembler";
    mainProgram = "aptor";
  };
}
