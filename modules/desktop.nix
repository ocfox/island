{ config, ... }:
{
  flake.modules.nixos.desktop =
    { pkgs, ... }:
    {
      services.gvfs.enable = true;

      my.packages = with pkgs; [
        gh
        nautilus
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
