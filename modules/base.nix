{ config, ... }:
let
  base = with config.flake.modules.nixos; [
    users
    nix
    i18n
    git
    helix
    shell
  ];
in
{
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      imports = base;
      services = {
        pcscd.enable = true;
        openssh = {
          enable = true;
          hostKeys = [
            {
              path = "/var/lib/ssh/ssh_host_ed25519_key";
              type = "ed25519";
            }
          ];
        };
        yggdrasil.enable = true;
      };
      hardware.enableRedistributableFirmware = true;
      environment.systemPackages = with pkgs; [
        git
        curl
        bind
        htop
        ripgrep
        age-plugin-yubikey
      ];
    };
}
