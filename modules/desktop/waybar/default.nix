{
  flake.modules.nixos.waybar =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      color_state = pkgs.writeShellScriptBin "waybar-color-state" ''
        GSETTINGS=${lib.getExe' pkgs.glib "gsettings"}
        cur=$($GSETTINGS get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
        if [ "$cur" = "prefer-dark" ]; then
          printf "暗"
        else
          printf "明"
        fi
      '';

      color_toggle = pkgs.writeShellScriptBin "waybar-color-toggle" ''
        GSETTINGS=${lib.getExe' pkgs.glib "gsettings"}
        cur=$($GSETTINGS get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
        if [ "$cur" = "prefer-dark" ]; then
          ${lib.getExe' pkgs.procps "pkill"} -USR2 -f "foot"
          $GSETTINGS set org.gnome.desktop.interface color-scheme "prefer-light"
        else
          ${lib.getExe' pkgs.procps "pkill"} -USR1 -f "foot"
          $GSETTINGS set org.gnome.desktop.interface color-scheme "prefer-dark"
        fi
      '';

      waybarSettings = [
        {
          layer = "top";
          position = "bottom";
          "modules-left" = [ "sway/workspaces" ];
          "modules-center" = [ "clock" ];
          "modules-right" = [
            "tray"
            "idle_inhibitor"
            "pulseaudio"
            # "memory"
            # "cpu"
            # "network"
            "custom/bright"
            "custom/color-switch"
          ];
          "sway/workspaces" = {
            "disable-scroll" = true;
            format = "{icon}";
            "all-outputs" = true;
            "format-icons" =
              [
                "い"
                "ろ"
                "は"
                "に"
                "ほ"
                "へ"
                "と"
                "ち"
                "り"
                "ぬ"
              ]
              |> lib.imap1 (i: icon: lib.nameValuePair (toString i) icon)
              |> lib.listToAttrs;
          };
          idle_inhibitor = {
            format = "{icon}";
            "format-icons" = {
              "activated" = "<s>待</s>";
              "deactivated" = "待";
            };
            tooltip = false;
          };
          pulseaudio = {
            format = "響 {volume}%";
            "format-muted" = "󰝟 Muted";
            "max-volume" = 200;
            "format-icons".default = [
              ""
              ""
              ""
            ];
            states.warning = 85;
            "scroll-step" = 1;
            "on-click" = "${lib.getExe pkgs.pwvucontrol}";
            tooltip = false;
          };
          clock = {
            interval = 1;
            format = "{:L%m月%d日(%a) %H時%M分}";
            tooltip = true;
            locale = "ja_JP.UTF-8";
            calendar = {
              format.today = "<span color='#ff6699'><b>{}</b></span>";
            };
            "tooltip-format" = "<span>{calendar}</span>";
          };
          battery = {
            states = {
              warning = 30;
              critical = 15;
            };
            format = "{icon} {capacity}%";
            "format-full" = "{icon} {capacity}%";
            "format-charging" = "󰂄 {capacity}%";
            "format-plugged" = " {capacity}%";
            "format-alt" = "{icon} {time}";
            "format-icons" = [
              ""
              ""
              ""
              ""
              ""
            ];
          };
          cpu = {
            interval = 1;
            format = "荷 {usage}%";
          };
          memory = {
            interval = 5;
            format = "憶 {used}/{total}";
          };
          network = {
            interval = 1;
            "format-wifi" = "󰖩 {essid}";
            "format-ethernet" = "{ipaddr}";
            "format-linked" = "󰖩 {essid}";
            "format-disconnected" = "󰖩 Disconnected";
            tooltip = true;
          };
          tray = {
            "icon-size" = 14;
            spacing = 5;
          };

          "custom/color-switch" = {
            exec = lib.getExe color_state;
            format = "{}";
            "on-click" = lib.getExe color_toggle;
            interval = "once";
          };

          "custom/bright" = {
            exec = "${pkgs.local.lumid}/bin/lumid -c card1-DP-2 get";
            format = "{}%";
            "on-scroll-up" = "${pkgs.local.lumid}/bin/lumid -c card1-DP-2 +1";
            "on-scroll-down" = "${pkgs.local.lumid}/bin/lumid -c card1-DP-2 -1";
            signal = 8;
            interval = "once";
            tooltip = false;
          };
        }
      ];
    in
    {
      my.packages = [
        pkgs.pwvucontrol
        pkgs.local.lumid
      ];

      programs.waybar.enable = true;

      my.config."waybar/config" = pkgs.writeText "waybar-config.json" (builtins.toJSON waybarSettings);
      my.config."waybar/style-dark.css" = ./style-dark.css;
      my.config."waybar/style-light.css" = ./style-light.css;
    };
}
