{
  fetchFromGitHub,
  sing-box,
}:

sing-box.overrideAttrs (oldAttrs: rec {
  version = "1.14.0-beta.15";

  src = fetchFromGitHub {
    owner = "SagerNet";
    repo = "sing-box";
    tag = "v${version}";
    hash = "sha256-fUaq2tyC2kTDveKhRMB+TQMZLL515MqkyK8mS85U7kI=";
  };

  vendorHash = "sha256-70cAuzVZY1F++xjoS+ZbWno7Y4uzi7FHIc2RFXFhMw0=";
})
