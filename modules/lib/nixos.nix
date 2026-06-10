{
  inputs,
  config,
  withSystem,
  lib,
  ...
}:
let
  inherit (inputs.nixpkgs.lib) mapAttrs nixosSystem optional;
in
{
  options.hosts = lib.mkOption {
    type = lib.types.lazyAttrsOf (
      lib.types.submodule {
        options = {
          system = lib.mkOption { type = lib.types.str; };
          stateVersion = lib.mkOption { type = lib.types.str; };
          hostKey = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          module = lib.mkOption { type = lib.types.deferredModule; };
        };
      }
    );
    default = { };
  };

  config.flake.nixosConfigurations = mapAttrs (
    name: host:
    withSystem host.system (
      { pkgs, ... }:
      nixosSystem {
        inherit pkgs;
        system = host.system;
        specialArgs = { inherit inputs; };
        modules =
          let
            nixos = config.flake.modules.nixos;
          in
          [
            host.module
            nixos.base
            { system.stateVersion = host.stateVersion; }
            {
              networking.hostName = name;
              nixpkgs.hostPlatform = host.system;
            }
          ]
          ++ optional (host.hostKey != null) {
            imports = [ inputs.kix.nixosModules.default ];
            kix.settings.hostPubkey = host.hostKey;
          }
          ++ optional (nixos ? ${name}) nixos.${name};
      }
    )
  ) config.hosts;
}
