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
        xdg.serverAutostart = true;
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
            background = "2d353b";
            foreground = "d3c6aa";
            regular0 = "2d353b";
            regular1 = "e67e80";
            regular2 = "a7c080";
            regular3 = "dbbc7f";
            regular4 = "7fbbb3";
            regular5 = "d699b6";
            regular6 = "83c092";
            regular7 = "9da9a0";
            bright0 = "7a8478";
            bright1 = "e67e80";
            bright2 = "a7c080";
            bright3 = "dbbc7f";
            bright4 = "7fbbb3";
            bright5 = "d699b6";
            bright6 = "83c092";
            bright7 = "d3c6aa";
          };
          colors-light = {
            background = "fdf6e3";
            foreground = "5c6a72";
            regular0 = "fdf6e3";
            regular1 = "f85552";
            regular2 = "8da101";
            regular3 = "dfa000";
            regular4 = "3a94c5";
            regular5 = "df69ba";
            regular6 = "35a77c";
            regular7 = "829181";
            bright0 = "a6b0a0";
            bright1 = "f85552";
            bright2 = "8da101";
            bright3 = "dfa000";
            bright4 = "3a94c5";
            bright5 = "df69ba";
            bright6 = "35a77c";
            bright7 = "5c6a72";
          };
        };
      };

      my.config."hyfetch.json" = pkgs.writeText "hyfetch-config.json" (
        builtins.toJSON {
          preset = "sapphic";
          mode = "rgb";
          auto_detect_light_dark = true;
          light_dark = "light";
          lightness = 0.9;
          color_align = {
            mode = "custom";
            custom_colors = {
              "1" = 0;
              "2" = 1;
            };
          };
          backend = "fastfetch";
          args = null;
          distro = null;
          pride_month_disable = false;
          custom_ascii_path = null;
        }
      );

      my.config."fastfetch/config.jsonc" = pkgs.writeText "fastfetch-config.jsonc" (
        builtins.toJSON {
          "$schema" = "https://github.com/fastfetch-cli/fastfetch/raw/master/doc/json_schema.json";
          modules = [
            "title"
            "separator"
            "os"
            "host"
            "kernel"
            "board"
            "uptime"
            "shell"
            "cursor"
            "terminal"
            "wm"
            "bootmgr"
            "memory"
            "cpu"
            "gpu"
            "packages"
            "terminalfont"
            "display"
            "de"
            "font"
            "colors"
          ];
        }
      );
    };
}
