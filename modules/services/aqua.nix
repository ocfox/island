{ ... }:
{
  flake.modules.nixos.aqua =
    {
      config,
      lib,
      pkgs,
      options,
      ...
    }:
    let
      cfg = config.services.aqua;
    in
    {
      meta.maintainers = [ "ocfox" ];

      options.services.aqua = {
        enable = lib.mkEnableOption "aqua activity tracking daemon";

        package = lib.mkPackageOption pkgs.local "aqua" { };

        serveAddr = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Address to bind the HTTP metrics and API server";
        };

        servePort = lib.mkOption {
          type = lib.types.port;
          default = 8765;
          description = "Port to listen on for HTTP metrics and API";
        };

        idleTimeoutMs = lib.mkOption {
          type = lib.types.int;
          default = 30000;
          description = "Inactivity duration in milliseconds before marking session as idle";
        };

        vmUrl = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Optional VictoriaMetrics import endpoint URL";
        };
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (lib.optionalAttrs (options ? systemd) {
            systemd.user.services.aqua = {
              description = "Aqua activity tracking daemon";
              after = [ "graphical-session.target" ];
              partOf = [ "graphical-session.target" ];
              wantedBy = [ "graphical-session.target" ];
              serviceConfig = {
                Type = "simple";
                Environment = [
                  "AQUA_DB=%h/.local/share/aqua/aqua.db"
                  "AQUA_AGENT_ID=%H"
                  "AQUA_IDLE_TIMEOUT_MS=${toString cfg.idleTimeoutMs}"
                  "AQUA_HTTP_ADDR=${cfg.serveAddr}"
                  "AQUA_HTTP_PORT=${toString cfg.servePort}"
                ] ++ lib.optional (cfg.vmUrl != "") "AQUA_VM_URL=${cfg.vmUrl}";
                ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/.local/share/aqua";
                ExecStart = "${cfg.package}/bin/aqua daemon";
                Restart = "on-failure";
                RestartSec = "3s";
              };
            };
          })
        ]
      );
    };
}
