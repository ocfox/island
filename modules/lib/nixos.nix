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
          useBase = lib.mkOption {
            type = lib.types.bool;
            default = true;
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
        modules =
          let
            nixos = config.flake.modules.nixos;
          in
          [
            host.module
            { system.stateVersion = host.stateVersion; }
            {
              networking.hostName = name;
              nixpkgs.hostPlatform = host.system;
            }
          ]
          ++ optional host.useBase nixos.base
          ++ optional (host.hostKey != null) {
            imports = [ config.flake.kix.nixosModule ];
            kix.hostPubkey = host.hostKey;
          }
          ++ optional (nixos ? ${name}) nixos.${name};
      }
    )
  ) config.hosts;
}
