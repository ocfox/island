{ config, ... }:
let
  inherit (config.flake.lib) mkHostModule;
  nixosModules = config.flake.modules.nixos;
in
{
  flake.modules.nixos.clare =
    { ... }:
    {
      imports = mkHostModule {
        stateVersion = "25.11";
        modules = with nixosModules; [
          vps
          {
            fileSystems."/" = {
              device = "/dev/disk/by-uuid/abf81274-ce56-4d1e-a613-b41aecf48ac8";
              fsType = "ext4";
            };
            swapDevices = [ { device = "/swapfile"; size = 69; } ];
            networking.interfaces.eth0.ipv4.addresses = [
              {
                address = "154.17.16.142";
                prefixLength = 32;
              }
            ];
            networking.defaultGateway = {
              address = "193.41.250.250";
              interface = "eth0";
            };
          }
        ];
      };
    };
}
