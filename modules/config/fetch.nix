{
  flake.modules.nixos.fetch =
    { pkgs, ... }:
    {
      my.packages = with pkgs; [
        hyfetch
        fastfetch
      ];

      my.config."hyfetch.json" = pkgs.writeText "hyfetch-config.json" (
        builtins.toJSON {
          preset = "unlabeled1";
          mode = "rgb";
          auto_detect_light_dark = true;
          light_dark = "light";
          lightness = 0.85;
          color_align = {
            mode = "custom";
            custom_colors = {
              "1" = 2;
              "2" = 0;
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
