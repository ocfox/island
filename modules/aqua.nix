{ ... }:
{
  flake.modules.nixos.aqua =
    { config, lib, pkgs, ... }:
    let
      cfg = config.services.aqua;
    in
    {
      options.services.aqua = {
        enable = lib.mkEnableOption "aqua activity tracking";

        serveAddr = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
        };

        servePort = lib.mkOption {
          type = lib.types.port;
          default = 8765;
        };

        idleTimeoutMs = lib.mkOption {
          type = lib.types.int;
          default = 30000;
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.user.services.aqua-agent = {
          description = "Aqua activity agent";
          after = [ "graphical-session.target" ];
          partOf = [ "graphical-session.target" ];
          wantedBy = [ "graphical-session.target" ];
          serviceConfig = {
            Type = "simple";
            Environment = [
              "AQUA_DB=%h/.local/share/aqua/aqua.db"
              "AQUA_AGENT_ID=%H"
              "AQUA_IDLE_TIMEOUT_MS=${toString cfg.idleTimeoutMs}"
            ];
            ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/.local/share/aqua";
            ExecStart = "${pkgs.local.aqua}/bin/aqua agent watch";
            Restart = "on-failure";
            RestartSec = "3s";
          };
        };

        systemd.user.services.aqua-serve = {
          description = "Aqua HTTP API";
          after = [ "aqua-agent.service" ];
          wantedBy = [ "default.target" ];
          serviceConfig = {
            Type = "simple";
            Environment = [
              "AQUA_DB=%h/.local/share/aqua/aqua.db"
              "AQUA_AGENT_ID=%H"
              "AQUA_HTTP_ADDR=${cfg.serveAddr}"
              "AQUA_HTTP_PORT=${toString cfg.servePort}"
            ];
            ExecStart = "${pkgs.local.aqua}/bin/aqua serve";
            Restart = "on-failure";
            RestartSec = "3s";
          };
        };
      };
    };
}
