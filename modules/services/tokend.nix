{ ... }:
{
  flake.modules.nixos.tokend =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.tokend;
    in
    {
      meta.maintainers = [ "ocfox" ];

      options.services.tokend = {
        enable = lib.mkEnableOption "tokend personal AI token usage exporter";

        package = lib.mkPackageOption pkgs.local "tokend" { };

        endpoint = lib.mkOption {
          type = lib.types.str;
          default = "https://s4r.in/api/tokens";
          description = "HTTP POST endpoint to push token usage metrics to";
        };

        intervalSeconds = lib.mkOption {
          type = lib.types.int;
          default = 300;
          description = "Collection interval in seconds";
        };

        secretFile = lib.mkOption {
          type = lib.types.nullOr (lib.types.either lib.types.path lib.types.str);
          default = null;
          description = ''
            File holding the Bearer authentication secret.
            Leave null if endpoint does not require authentication.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        systemd.user.services.tokend = {
          description = "Personal AI token usage exporter daemon";
          after = [ "network.target" ];
          wantedBy = [ "default.target" ];

          serviceConfig = {
            Type = "simple";
            ExecStart =
              "${lib.getExe cfg.package}"
              + " -endpoint ${cfg.endpoint}"
              + " -interval ${toString cfg.intervalSeconds}"
              + (lib.optionalString (cfg.secretFile != null) " -secret-file ${cfg.secretFile}");
            Restart = "on-failure";
            RestartSec = 10;
          };
        };
      };
    };
}
