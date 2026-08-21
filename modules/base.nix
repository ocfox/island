{ config, ... }:
{
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      imports = with config.flake.modules.nixos; [
        users
        dotfiles
        nix
        i18n
        git
        shell
      ];
      services = {
        tailscale.enable = true;
        pcscd.enable = true;
        openssh = {
          enable = true;
          settings = {
            PasswordAuthentication = false;
            KbdInteractiveAuthentication = false;
          };
          hostKeys = [
            {
              path = "/var/lib/ssh/ssh_host_ed25519_key";
              type = "ed25519";
            }
          ];
        };
      };
      hardware.enableRedistributableFirmware = true;
      environment.systemPackages = with pkgs; [
        curl
        bind
        htop
        ripgrep
        age-plugin-yubikey
      ];
    };
}
