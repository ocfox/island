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
    rev = "1757824001ebbe7296b388c63e4fe3348b03a379";
    hash = "sha256-iuiYEaLbe8usORY0RD5WHZ/7EIJHJ/zs6V00gne3/Fs=";
  };

  vendorHash = null;

  env.CGO_ENABLED = 0;

  meta = {
    description = "Sing-box 1.14 subscription hub and configuration assembler";
    mainProgram = "aptor";
  };
}
