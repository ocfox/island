{
  lib,
  buildGoModule,
}:

buildGoModule {
  pname = "tokend";
  version = "0.1.0";

  src = ./.;

  vendorHash = "sha256-7IC/p5GlD2EZkDXQzkaZ7E19S/ABKEBsg68vt8pykis=";

  env.CGO_ENABLED = 0;

  meta = {
    description = "Lightweight personal AI token usage exporter daemon";
    mainProgram = "tokend";
  };
}
