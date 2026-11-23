{ ... }:
{
  flake.modules.nixos.vertere =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.vertere;
    in
    {
      meta.maintainers = [ "ocfox" ];

      options.services.vertere = {
        enable = lib.mkEnableOption "the Vertere translation daemon";

        package = lib.mkPackageOption pkgs.local "vertere" { };

        environmentFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          example = "/run/secrets/vertere";
          description = ''
            File holding `API_KEY=...`, read at startup. Keep it out of the
            Nix store — point at a secret manager's output or a path with
            mode 0600.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        systemd.user.services.vertere = {
          description = "Vertere translation daemon";
          partOf = [ "graphical-session.target" ];
          after = [ "graphical-session.target" ];
          wantedBy = [ "graphical-session.target" ];

          serviceConfig = {
            Type = "dbus";
            BusName = "me.ocfox.Vertere";
            ExecStart = "${lib.getExe cfg.package} daemon";
            EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
            Restart = "on-failure";
            RestartSec = 2;
          };
        };
      };
    };
}
