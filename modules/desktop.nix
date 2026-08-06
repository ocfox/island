{ config, ... }:
{
  flake.modules.nixos.desktop =
    { pkgs, ... }:
    {
      my.packages = with pkgs; [
        gh
        yazi
      ];

      imports = with config.flake.modules.nixos; [
        helix
        xdg
        fonts
        fcitx
        audio
        earlyoom
        fetch

        foot
        mako
        waybar
        gtk
        mpv
        sway
      ];
    };
}
