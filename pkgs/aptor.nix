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
    rev = "69b73f312c40493242d6516992259dfb0f9c3784";
    hash = "sha256-Dnseg4WDxWj+yONIXE63EmN0ZBE63A+IDzA/36Lx54I=";
  };

  vendorHash = null;

  env.CGO_ENABLED = 0;

  meta = {
    description = "Sing-box 1.14 subscription hub and configuration assembler";
    mainProgram = "aptor";
  };
}
