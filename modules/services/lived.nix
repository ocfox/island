{ ... }:
{
  flake.modules.nixos.lived =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.lived;
    in
    {
      meta.maintainers = [ "ocfox" ];

      options.services.lived = {
        enable = lib.mkEnableOption "lived desktop presence and Spotify exporter daemon";

        package = lib.mkPackageOption pkgs.local "lived" { };

        endpoint = lib.mkOption {
          type = lib.types.str;
          default = "wss://live.s4r.in/presence/push";
          description = "WebSocket endpoint to stream live presence and Spotify state to";
        };

        idleTimeoutSeconds = lib.mkOption {
          type = lib.types.int;
          default = 300;
          description = "Wayland input idle timeout in seconds before marking status as idle";
        };

        secretFile = lib.mkOption {
          type = lib.types.nullOr (lib.types.either lib.types.path lib.types.str);
          default = null;
          description = ''
            File holding the Bearer authentication secret.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        systemd.user.services.lived = {
          description = "Personal desktop presence and Spotify exporter daemon";
          after = [
            "graphical-session.target"
            "network-online.target"
          ];
          partOf = [ "graphical-session.target" ];
          wantedBy = [ "graphical-session.target" ];

          serviceConfig = {
            Type = "simple";
            ExecStart =
              "${lib.getExe cfg.package}"
              + " -endpoint ${cfg.endpoint}"
              + " -idle-timeout ${toString cfg.idleTimeoutSeconds}"
              + (lib.optionalString (cfg.secretFile != null) " -secret-file ${cfg.secretFile}");
            Restart = "always";
            RestartSec = 5;
          };
        };
      };
    };
}
