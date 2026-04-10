{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule {
  pname = "ctct";
  version = "1.0";

  src = fetchFromGitHub {
    owner = "ocfox";
    repo = "ctct";
    rev = "a6d620517d4e8d833308683f81aa0cb2886b551f";
    hash = "sha256-xDotrHWzC/5aaekZxekluqDxUL6EUXS2UKdwJMvZyIs=";
  };

  vendorHash = null;

  ldflags = [ "-s" ];

  meta.mainProgram = "ctct";
}
