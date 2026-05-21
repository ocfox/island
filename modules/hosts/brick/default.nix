{ config, ... }:
let
  inherit (config.flake.lib) mkHostModule;
  nixosModules = config.flake.modules.nixos;
in
{
  flake.modules.nixos.brick =
    { pkgs, ... }:
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
            my.packages = [ pkgs.qbittorrent ];
            services.blueman.enable = true;
            networking = {
              nameservers = [ "10.10.0.157" ];
              firewall.enable = false;
            };
            boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
          }
        ];
      };
    };
}
