{ config, ... }:
let
  inherit (config.flake.lib) mkHostModule;
  nixosModules = config.flake.modules.nixos;
in
{
  flake.modules.nixos.wall =
    { pkgs, config, ... }:
    {
      imports = mkHostModule {
        stateVersion = "25.11";
        modules = with nixosModules; [
          boot
          disko
          facter
          desktop
          {
            facter.reportPath = ./facter.json;
            services.blueman.enable = true;
            networking = {
              firewall.enable = false;
              nameservers = [ "10.10.0.157" ];
              proxy.default = "http://10.10.0.157:7890";
            };
            hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];
            boot.kernelParams = [
              "i915.force_probe=46d0"
              "i915.enable_guc=3"
            ];
            environment.systemPackages = [ pkgs.kodi-gbm ];
            users.users.${config.my.name}.extraGroups = [ "input" ];
          }
        ];
      };
    };
}
