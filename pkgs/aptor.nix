{
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule {
  pname = "aptor";
  version = "0-unstable-2026-08-17";

  src = fetchFromGitHub {
    owner = "ocfox";
    repo = "aptor";
    rev = "5d4c8bc73a33b916c9be273b028c54894d8aaf9f";
    hash = "sha256-7rUOPfvmD/Ge9jnRnOb9vWL4bxrWaYNOrHwb9h1UoWM=";
  };

  vendorHash = null;

  env.CGO_ENABLED = 0;

  meta = {
    description = "Sing-box 1.14 subscription hub and configuration assembler";
    mainProgram = "aptor";
  };
}
