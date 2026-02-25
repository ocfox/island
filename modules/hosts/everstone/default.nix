{ config, ... }:
let
  inherit (config.flake.lib) mkHostModule;
  nixosModules = config.flake.modules.nixos;
in
{
  flake.modules.nixos.everstone =
    {
      pkgs,
      ...
    }:
    {
      imports = mkHostModule {
        stateVersion = "25.11";
        # hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIoT6gPSX5fd1bGnANf5xj1HMKEhNgA3CAN0TgiAP6lJ root@brick";
        modules = with nixosModules; [
          boot
          facter

          desktop

          { facter.reportPath = ./facter.json; }
          {
            fileSystems."/" = {
              device = "/dev/disk/by-uuid/fe0ecfb9-db21-43f0-915a-70c37765f181";
              fsType = "btrfs";
            };

            fileSystems."/boot" = {
              device = "/dev/disk/by-uuid/3307-5F4E";
              fsType = "vfat";
            };
          }
          { my.packages = [ pkgs.qbittorrent ]; }
          { services.blueman.enable = true; }
          { networking.firewall.enable = false; }
          { boot.binfmt.emulatedSystems = [ "aarch64-linux" ]; }
        ];
      };
    };
}
