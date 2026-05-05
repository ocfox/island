{ inputs, ... }:
{
  imports = [ inputs.kix.flakeModules.default ];
  flake.kix = {
    identity = inputs.self + "/secrets/age-yubikey-identity-de5ab175.txt";
    nodes = inputs.self.nixosConfigurations;
  };
}
