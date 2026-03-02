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

          {
            hardware.graphics = {

              extraPackages = with pkgs; [
                intel-media-driver
                vpl-gpu-rt
                intel-compute-runtime
              ];
            };
            hardware.enableRedistributableFirmware = true;
            boot.kernelParams = [ "i915.force_probe=56a1" "i915.enable_guc=3" ];
            environment.sessionVariables = {
              LIBVA_DRIVER_NAME = "iHD";
            };
          }

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
