{ config, ... }:
{
  flake.modules.nixos.desktop =
    { pkgs, ... }:
    {
      my.packages = with pkgs; [
        gh
        yazi
        zed-editor
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
        gtk
        mpv
        sway
      ];
    };
}
