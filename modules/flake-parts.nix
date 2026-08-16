{ inputs, withSystem, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.modules ];

  perSystem =
    {
      system,
      config,
      lib,
      pkgs,
      ...
    }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config = {
          allowUnfreePredicate = _pkg: true;
        };
        overlays = [
          inputs.self.overlays.default
        ];
      };
      packages = lib.packagesFromDirectoryRecursive {
        callPackage = lib.callPackageWith pkgs;
        directory = ../pkgs;
      };
    };

  flake = {
    overlays.default =
      _final: prev:
      withSystem prev.stdenv.hostPlatform.system (
        { config, ... }:
        {
          local = config.packages;
        }
      );
  };
}
