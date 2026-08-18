{
  fetchFromGitHub,
  sing-box,
}:

sing-box.overrideAttrs (oldAttrs: rec {
  version = "1.14.0-beta.17";

  src = fetchFromGitHub {
    owner = "SagerNet";
    repo = "sing-box";
    tag = "v${version}";
    hash = "sha256-7kn2UcCbea3v203U4knzbCKQECPCobIQXMy705RYucQ=";
  };

  vendorHash = "sha256-9Cv3WJG2C3yMk1d8UCLMIhgM5Q9dYAYp7A0F1LdZm/s=";
})
