{
  flake.modules.nixos.foot =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    {
      programs.foot = {
        enable = true;
        settings = {
          url.launch = "foot -e xdg-open \${url}";
          main = {
            term = "xterm-256color";
            font = "JetBrainsMono Nerd Font:size=16";
            "dpi-aware" = "yes";
          };
          mouse = {
            "hide-when-typing" = "yes";
          };
          colors-dark = {
            alpha = 0.95;
            background = "2b3339";
            foreground = "d8caac";
          };
        };
      };
    };
}
