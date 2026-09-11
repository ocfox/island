{
  flake.modules.nixos.persona =
    { lib, pkgs, config, ... }:
    let
      qs = lib.getExe' pkgs.quickshell "qs";
      # QML modules the shell imports that quickshell does not ship itself:
      # CavaMonitor (CavaVisualizer.qml) and QtMultimedia (Resume.qml).
      qmlPath = lib.concatStringsSep ":" [
        "${pkgs.local.qt6-cava-plugin}/lib/qt6/qml"
        "${pkgs.qt6.qtmultimedia}/${pkgs.qt6.qtbase.qtQmlPrefix}"
      ];
      # QtMultimedia loads its media backend as a Qt plugin.
      pluginPath = "${pkgs.qt6.qtmultimedia}/${pkgs.qt6.qtbase.qtPluginPrefix}";
      # org.gnome.desktop.interface is not in the session's XDG_DATA_DIRS, so
      # bare gsettings calls fail with "No schemas installed".
      schemaDir = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";
    in
    {
      my = {
        packages = [ pkgs.quickshell ];
        config."quickshell/persona" = pkgs.local.persona-shell;
      };

      # The shell asks for these by family name; Bahnschrift Condensed is a
      # Microsoft font and has no nixpkgs equivalent, so it falls back.
      fonts.packages = with pkgs; [
        montserrat
        material-symbols
      ];

      systemd.user.services.persona-shell = {
        description = "Persona Quickshell desktop shell";
        after = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];

        # A systemd user unit starts with no usable PATH, and `path` replaces it
        # rather than extending it. The session directories have to come along:
        # Searchapp launches .desktop entries as children of this service, and
        # most of them have a bare command name in Exec=.
        path = [
          "/run/wrappers"
          "/etc/profiles/per-user/${config.my.name}"
          "/run/current-system/sw"
        ]
        ++ (with pkgs; [
          bash # sh -c ... (SysInfo, BrightnessOsd)
          coreutils # ls, head, who, wc, df
          gawk # SysInfo's df pipeline
          glib # gsettings — the only one not already in the system path
          procps # pkill (theme toggle)
          systemd # loginctl (power menu)
        ]);
        # No networkmanager: this host is networkd + iwd, and the shell's nmcli
        # based NetInfo has been dropped from the fork.

        serviceConfig = {
          Type = "simple";
          Environment = [
            "QML_IMPORT_PATH=${qmlPath}"
            "QML2_IMPORT_PATH=${qmlPath}"
            "QT_PLUGIN_PATH=${pluginPath}"
            "GSETTINGS_SCHEMA_DIR=${schemaDir}"
          ];
          ExecStart = "${qs} -c persona";
          Restart = "on-failure";
          RestartSec = "3s";
        };
      };
    };
}
