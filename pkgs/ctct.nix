{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "ctct";
  version = "1";

  src = fetchFromGitHub {
    owner = "ocfox";
    repo = "ctct";
    rev = "8dc7dd97c7807cd4fcd9b61a794c50d4ec702ee3";
    hash = "sha256-84qs0EXwy5xss6gmh/4QNX92i2C86P6Vqg3xK6wft1U=";
  };

  cargoHash = "sha256-yvXrlpUMxxiAHsaEGyF7uuA2cZDAI9Qu5JPo5VXNhBs=";

  meta.mainProgram = "ctct";
})
