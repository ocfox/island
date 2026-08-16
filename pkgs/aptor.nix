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
    rev = "master";
    hash = "sha256-w72ErGmEkNkROqpEzgLNhX/X1OlNDfFxBLSr48I2Xr4=";
  };

  vendorHash = null;

  env.CGO_ENABLED = 0;

  meta = {
    description = "Sing-box 1.14 subscription hub and configuration assembler";
    mainProgram = "aptor";
  };
}
