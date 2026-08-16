{ ... }:
{
  flake.modules.nixos.aptor =
    {
      config,
      lib,
      pkgs,
      options,
      ...
    }:
    let
      cfg = config.services.aptor;
    in
    {
      meta.maintainers = [ "ocfox" ];

      options.services.aptor = {
        enable = lib.mkEnableOption "Aptor sing-box subscription hub";

        package = lib.mkPackageOption pkgs.local "aptor" { };

        listenAddr = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
        };

        listenPort = lib.mkOption {
          type = lib.types.port;
          default = 8080;
        };

        domain = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "aptor.s4r.in";
          description = "Domain name to configure ACME certificate and Caddy reverse proxy";
        };
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (lib.optionalAttrs (options ? systemd) {
            kix.secrets.aptor.mode = "640";

            systemd.services.aptor = {
              description = "Aptor sing-box subscription hub";
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "simple";
                DynamicUser = true;
                LoadCredential = [ "aptor.json:${config.kix.secrets.aptor.path}" ];
                ExecStart = "${cfg.package}/bin/aptor server --config %d/aptor.json --listen ${cfg.listenAddr}:${toString cfg.listenPort}";
                Restart = "on-failure";
                RestartSec = "5s";
              };
            };
          })

          (lib.mkIf (cfg.domain != null) {
            security.acme.certs.${cfg.domain} = {
              dnsProvider = "cloudflare";
              environmentFile = config.kix.secrets.cf-dns.path;
              group = "caddy";
            };

            services.caddy.virtualHosts.${cfg.domain} = {
              useACMEHost = cfg.domain;
              extraConfig = ''
                reverse_proxy ${cfg.listenAddr}:${toString cfg.listenPort}
              '';
            };
          })
        ]
      );
    };
}
