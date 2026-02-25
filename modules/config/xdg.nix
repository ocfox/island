{
  flake.modules.nixos.xdg =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = [
        pkgs.nautilus
        pkgs.sioyek
      ];
      services.gnome.sushi.enable = true;
      xdg = {
        terminal-exec.enable = true;
        terminal-exec.settings.default = [ "foot.desktop" ];
        mime = {
          enable = true;
          defaultApplications = {
            "application/x-xdg-protocol-tg" = [ "org.telegram.desktop.desktop" ];
            "x-scheme-handler/tg" = [ "org.telegram.desktop.desktop" ];
            "inode/directory" = [ "org.gnome.Nautilus.desktop" ];
            "application/pdf" = [ "sioyek.desktop" ];
            "text/plain" = [ "helix.desktop" ];
          }
          // lib.genAttrs [
            "x-scheme-handler/unknown"
            "x-scheme-handler/about"
            "x-scheme-handler/http"
            "x-scheme-handler/https"
            "x-scheme-handler/mailto"
            "text/html"
          ] (_: "google-chrome.desktop");
        };
        portal = {
          enable = true;
          wlr.enable = true;
          config.common.default = "wlr";
        };
      };
    };
}
