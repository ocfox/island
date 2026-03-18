{ config, ... }:
{
  flake.modules.nixos.desktop =
    { pkgs, ... }:
    {
      programs.sway.enable = true;
      environment.systemPackages = [ pkgs.yazi ];
      imports = with config.flake.modules.nixos; [
        xdg
        fonts
        fcitx
        audio

        # dns

        foot
        mako
        waybar
        gtk
        mpv
        sway
      ];
    };
}
