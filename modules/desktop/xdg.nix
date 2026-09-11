{
  flake.modules.nixos.xdg =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      # my.packages = [ pkgs.sioyek ];

      # ~/.config/<desktop>-mimeapps.list outranks ~/.config/mimeapps.list, so apps
      # writing the latter can no longer override what is declared here.
      my.config."sway-mimeapps.list" = config.environment.etc."xdg/mimeapps.list".source;

      xdg = {
        terminal-exec.enable = true;
        terminal-exec.settings.default = [ "foot.desktop" ];
        mime = {
          enable = true;
          defaultApplications =
            let
              associate = desktop: mimes: lib.genAttrs mimes (_: desktop);
            in
            {
              "x-scheme-handler/tg" = [ "org.telegram.desktop.desktop" ];
              "x-scheme-handler/tonsite" = [ "org.telegram.desktop.desktop" ];
              "x-scheme-handler/discord" = [ "vesktop.desktop" ];
              "x-scheme-handler/claude-cli" = [ "claude-code-url-handler.desktop" ];
              "inode/directory" = [ "org.gnome.Nautilus.desktop" ];
            }
            // associate "Helix.desktop" [
              "text/plain"
              "text/markdown"
            ]
            // associate "swayimg.desktop" [
              "image/png"
              "image/jpeg"
              "image/gif"
              "image/webp"
              "image/avif"
              "image/tiff"
              "image/svg+xml"
            ]
            // associate "zen.desktop" [
              "x-scheme-handler/unknown"
              "x-scheme-handler/about"
              "x-scheme-handler/http"
              "x-scheme-handler/https"
              "x-scheme-handler/mailto"
              "text/html"
              "application/xhtml+xml"
            ];
        };
        portal = {
          enable = true;
          wlr.enable = true;
          extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
          config.common = {
            default = [ "gtk" ];
            "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
            "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
          };
        };
      };
    };
}
