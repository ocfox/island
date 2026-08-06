{ config, ... }:
{
  flake.modules.nixos.desktop =
    { pkgs, ... }:
    {
      programs.sway.enable = true;
      environment.systemPackages = [ pkgs.yazi ];
      imports = with config.flake.modules.nixos; [
        helix
        xdg
        fonts
        fcitx
        audio
        earlyoom

        starship

        foot
        mako
        waybar
        gtk
        mpv
        sway
      ];
    };
}
