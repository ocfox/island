{
  inputs,
  config,
  withSystem,
  ...
}:
let
  inherit (inputs.nixpkgs.lib) mapAttrs nixosSystem optional;
in
{
  flake.lib = {
    mkHostModule =
      {
        modules ? [ ],
        stateVersion,
        hostKey ? null,
      }:
      [
        config.flake.modules.nixos.base
        { system.stateVersion = stateVersion; }
      ]
      ++ optional (hostKey != null) {
        imports = [ inputs.kix.nixosModules.default ];
        kix.settings.hostPubkey = hostKey;
      }
      ++ modules;

    mkNixos =
      system: name:
      withSystem system (
        { pkgs, ... }:
        nixosSystem {
          inherit system pkgs;
          specialArgs = { inherit inputs; };
          modules = [
            config.flake.modules.nixos.${name}
            {
              networking.hostName = name;
              nixpkgs.hostPlatform = system;
            }
          ];
        }
      );

    mkNixosFromAttrs = hosts: mapAttrs (name: system: config.flake.lib.mkNixos system name) hosts;
  };
}
