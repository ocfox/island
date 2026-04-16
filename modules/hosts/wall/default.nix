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
        modules =
          with nixosModules;
          [
            boot
            disko
            facter
            desktop
          ]
          ++ [
            { facter.reportPath = ./facter.json; }
            { services.blueman.enable = true; }
            { networking.firewall.enable = false; }
            { networking.nameservers = [ "10.10.0.157" ]; }
            { networking.proxy.default = "http://10.10.0.157:7890"; }
            { hardware.graphics.extraPackages = [ pkgs.intel-media-driver ]; }
            { hardware.enableRedistributableFirmware = true; }
            {
              boot.kernelParams = [
                "i915.force_probe=46d0"
                "i915.enable_guc=3"
              ];
            }
            {
              environment.systemPackages = [
                pkgs.kodi-gbm
              ];
              users.users.${config.my.name}.extraGroups = [ "input" ];
            }
            # {
            #   vaultix.secrets.vault = {
            #     file = ../../secrets/vault.age;
            #     mode = "640";
            #   };
            # }
          ];
        stateVersion = "25.11";
        # hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII3bQFO5LoC420iUupO9kJBBLnujh/QCURi64LvT5mmT root@brick";
      };
    };
}
