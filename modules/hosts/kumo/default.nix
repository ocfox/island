{ config, ... }:
let
  inherit (config.flake.lib) mkHostModule;
  nixosModules = config.flake.modules.nixos;
in
{
  flake.modules.nixos.kumo =
    { ... }:
    {
      imports = mkHostModule {
        stateVersion = "25.11";
        modules = with nixosModules; [
          vps
          disko
          {
            systemd.network.networks."10-eth0" = {
              address = [
                "2401:b60:e0fd:11::2/64"
                "2401:b60:e0fd:151::2/64"
                "2401:b60:e0fd:3d::2/64"
                "2401:b60:e0fd:2b::2/64"
              ];
              networkConfig = {
                DHCP = "no";
                IPv6AcceptRA = false;
              };
              routes = [
                { Gateway = "2401:b60:e0fd:2b::1"; }
              ];
            };
          }
        ];
      };
    };
}
