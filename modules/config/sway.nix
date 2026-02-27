{
  flake.modules.nixos.sway =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      bg = pkgs.fetchurl {
        url = "https://image.tmdb.org/t/p/original/iLis4CUhZ5cHmMEqEBYF7XcQl27.jpg";
        name = "sawa";
        hash = "sha256-5+uyUEmkp++hjc6xCis9MVXE0PKzKPHZZNrDIYD3qnQ=";
      };
      ed = pkgs.fetchurl {
        url = "https://image.tmdb.org/t/p/original/s2XhIP2HQHbG4aLnIBqQsYCWEDB.jpg";
        name = "ed";
        hash = "sha256-FHRa6itAqi5i0XEqPbC1ueCoqKicbM7Qmvomwom/oX4=";
      };
      config = ''
        font pango:monospace 8.000000
        floating_modifier Mod4
        default_border pixel 2
        default_floating_border normal 2
        hide_edge_borders smart
        focus_wrapping no
        focus_follows_mouse yes
        focus_on_window_activation smart
        mouse_warping output
        workspace_layout default
        workspace_auto_back_and_forth no
        client.focused #83b6af #83b6af #ffffff #a7c080 #83b6af
        client.focused_inactive #333333 #5f676a #ffffff #484e50 #5f676a
        client.unfocused #2b3339 #2b3339 #888888 #a7c080 #2b3339
        client.urgent #e68183 #e68183 #ffffff #a7c080 #e68183
        client.placeholder #000000 #0c0c0c #ffffff #000000 #0c0c0c
        client.background #ffffff

        bindsym Mod4+0 workspace number 10
        bindsym Mod4+1 workspace number 1
        bindsym Mod4+2 workspace number 2
        bindsym Mod4+3 workspace number 3
        bindsym Mod4+4 workspace number 4
        bindsym Mod4+5 workspace number 5
        bindsym Mod4+6 workspace number 6
        bindsym Mod4+7 workspace number 7
        bindsym Mod4+8 workspace number 8
        bindsym Mod4+9 workspace number 9
        bindsym Mod4+Down focus down
        bindsym Mod4+Left focus left
        bindsym Mod4+Return exec ${lib.getExe pkgs.foot}
        bindsym Mod4+Right focus right
        bindsym Mod4+Shift+0 move container to workspace number 10
        bindsym Mod4+Shift+1 move container to workspace number 1
        bindsym Mod4+Shift+2 move container to workspace number 2
        bindsym Mod4+Shift+3 move container to workspace number 3
        bindsym Mod4+Shift+4 move container to workspace number 4
        bindsym Mod4+Shift+5 move container to workspace number 5
        bindsym Mod4+Shift+6 move container to workspace number 6
        bindsym Mod4+Shift+7 move container to workspace number 7
        bindsym Mod4+Shift+8 move container to workspace number 8
        bindsym Mod4+Shift+9 move container to workspace number 9
        bindsym Mod4+Shift+Down move down
        bindsym Mod4+Shift+Left move left
        bindsym Mod4+Shift+Right move right
        bindsym Mod4+Shift+Up move up
        bindsym Mod4+Shift+a exec ${lib.getExe pkgs.local.macshot}
        bindsym Mod4+Shift+c reload
        bindsym Mod4+Shift+d exec ${lib.getExe' pkgs.wireplumber "wpctl"} set-volume @DEFAULT_AUDIO_SINK@ 5%-
        bindsym Mod4+Shift+e exec ${lib.getExe pkgs.local.powermenu}
        bindsym Mod4+Shift+h move left
        bindsym Mod4+Shift+j move down
        bindsym Mod4+Shift+k move up
        bindsym Mod4+Shift+l move right
        bindsym Mod4+Shift+m exec ${lib.getExe pkgs.local.monitor-toggle}
        bindsym Mod4+Shift+minus move scratchpad
        bindsym Mod4+Shift+p exec ${pkgs.sway-contrib.grimshot}/bin/grimshot copy output
        bindsym Mod4+Shift+q kill
        bindsym Mod4+Shift+r exec ${lib.getExe pkgs.local.recorder-toggle}
        bindsym Mod4+Shift+s exec ${pkgs.sway-contrib.grimshot}/bin/grimshot copy area
        bindsym Mod4+Shift+u exec ${lib.getExe' pkgs.wireplumber "wpctl"} set-volume @DEFAULT_AUDIO_SINK@ 5%+
        bindsym Mod4+Up focus up
        bindsym Mod4+a focus parent
        bindsym Mod4+apostrophe exec ${lib.getExe pkgs.local.swaylock}
        bindsym Mod4+b splith
        bindsym Mod4+d move scratchpad
        bindsym Mod4+e layout toggle split
        bindsym Mod4+f fullscreen toggle
        bindsym Mod4+h focus left
        bindsym Mod4+i scratchpad show
        bindsym Mod4+j focus down
        bindsym Mod4+k focus up
        bindsym Mod4+l focus right
        bindsym Mod4+minus scratchpad show
        bindsym Mod4+o exec ${lib.getExe pkgs.fuzzel}
        bindsym Mod4+r mode resize
        bindsym Mod4+s layout stacking
        bindsym Mod4+space floating toggle
        bindsym Mod4+v splitv
        bindsym Mod4+w layout tabbed

        output "HDMI-A-1" {
          bg ${bg} fill
          mode 3840x2160
          scale 3
        }

        output "DP-2" {
          bg ${ed} fill
          mode 3840x2160
          position 0 0
          scale 3
        }

        mode "resize" {
          bindsym Down resize grow height 10 px
          bindsym Escape mode default
          bindsym Left resize shrink width 10 px
          bindsym Return mode default
          bindsym Right resize grow width 10 px
          bindsym Up resize shrink height 10 px
          bindsym h resize shrink width 10 px
          bindsym j resize grow height 10 px
          bindsym k resize shrink height 10 px
          bindsym l resize grow width 10 px
        }


        set $my_cursor macOS
        set $my_cursor_size 24

        seat seat0 xcursor_theme $my_cursor $my_cursor_size
        exec_always {
            gsettings set org.gnome.desktop.interface cursor-theme $my_cursor
            gsettings set org.gnome.desktop.interface cursor-size $my_cursor_size
        }

        exec "${pkgs.dbus}/bin/dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP XDG_SESSION_TYPE; systemctl --user start sway-session.target" 

        assign [app_id="google-chrome"] 1
        assign [app_id="org.telegram.desktop"] 3
        for_window [title="Feishu Meetings"] floating enable

        exec uwsm app -- fcitx5 -d

        exec uwsm app -- google-chrome
        exec uwsm app -- Telegram

        workspace "10" output "HDMI-A-1"
        titlebar_border_thickness 0
        titlebar_padding 1
      '';
    in
    {
      my = {
        packages = with pkgs; [
          swaybg
          wl-clipboard
          wireplumber
          sway-contrib.grimshot
          google-chrome
          telegram-desktop
        ];
        config.sway = {
          "config" = pkgs.writeText "sway-config" config;
        };
      };

      environment.sessionVariables = {
        NIXOS_OZONE_WL = "1";
        QT_IM_MODULES = "wayland;fcitx";
      };

      programs = {
        sway = {
          enable = true;
          wrapperFeatures.gtk = true;
          xwayland.enable = false;
        };
        uwsm = {
          enable = true;
          waylandCompositors.sway = {
            prettyName = "sway";
            comment = "Sway compositor managed by UWSM";
            binPath = "/run/current-system/sw/bin/sway";
          };
        };
      };

      services.gnome.gnome-keyring.enable = true;
      security.pam.services.login.enableGnomeKeyring = true;
    };
}
