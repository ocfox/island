{
  flake.modules.nixos.gtk =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      settingsIniContent = lib.generators.toINI { } {
        Settings = {
          gtk-theme-name = "Adwaita-dark";
          gtk-icon-theme-name = "Numix-Circle";
          gtk-cursor-theme-name = "macOS";
          gtk-application-prefer-dark-theme = 1;
          gtk-cursor-theme-size = 24;
          gtk-xft-hinting = 1;
          gtk-xft-hintstyle = "hintslight";
        };
      };

      gtk2Content = ''
        gtk-theme-name = "Adwaita-dark"
        gtk-icon-theme-name = "Numix-Circle"
        gtk-cursor-theme-name = "macOS"
        gtk-cursor-theme-size = 24
      '';
    in
    {
      my.packages = [
        pkgs.gnome-themes-extra
        pkgs.numix-icon-theme-circle
        pkgs.apple-cursor
      ];

      my.config."gtk-3.0/settings.ini" = pkgs.writeText "gtk3-settings.ini" settingsIniContent;
      my.config."gtk-4.0/settings.ini" = pkgs.writeText "gtk4-settings.ini" settingsIniContent;
      my.config."gtk-2.0/gtkrc" = pkgs.writeText "gtkrc-2.0" gtk2Content;
    };
}
