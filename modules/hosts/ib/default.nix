{ inputs, config, ... }:
let
  inherit (config.flake.lib) mkHostModule;
  nixosModules = config.flake.modules.nixos;
in
{
  flake.modules.nixos.ib =
    {
      pkgs,
      ...
    }:
    {
      imports = mkHostModule {
        stateVersion = "25.11";
        modules = with nixosModules; [
          inputs.jovian.nixosModules.default
          boot
          disko

          desktop
          { jovian.devices.steamdeck.enable = true; }
          { networking.networkmanager.enable = true; }
        ];
      };
    };
}
