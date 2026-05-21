{ config, ... }:
let
  inherit (config.flake.lib) mkHostModule;
  nixosModules = config.flake.modules.nixos;
in
{
  flake.modules.nixos.mizu =
    { pkgs, ... }:
    {
      imports = mkHostModule {
        stateVersion = "25.11";
        modules = with nixosModules; [
          vps
          {
            fileSystems."/" = {
              device = "/dev/disk/by-uuid/580fd907-a2af-478d-adf1-7a70edcca3be";
              fsType = "ext4";
            };
            swapDevices = [ { device = "/swapfile"; size = 1175; } ];
            environment.systemPackages = with pkgs; [ hysteria tmux ];
            boot.kernel.sysctl."net.ipv6.conf.eth0.accept_ra" = false;
            boot.kernel.sysctl."net.ipv6.conf.eth0.autoconf" = false;
          }
        ];
      };
    };
}
