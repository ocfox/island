{ ... }:
{
  flake.modules.nixos.sub-relay =
    { config, lib, ... }:
    let
      cfg = config.services.sub-relay;
    in
    {
      options.services.sub-relay = {
        enable = lib.mkEnableOption "Universal subscription relay proxy in Caddy";
        domain = lib.mkOption {
          type = lib.types.str;
          default = "relay.s4r.in";
          description = "Domain name for the relay service";
        };
        secretName = lib.mkOption {
          type = lib.types.str;
          default = "relay-token";
          description = "Name of the secret containing RELAY_TOKEN=...";
        };
      };

      config = lib.mkIf cfg.enable {
        kix.secrets.${cfg.secretName} = {
          mode = "640";
          group = "caddy";
        };

        systemd.services.caddy.serviceConfig.EnvironmentFile = [
          config.kix.secrets.${cfg.secretName}.path
        ];

        security.acme.certs = lib.mkIf (cfg.domain != null) {
          ${cfg.domain} = {
            dnsProvider = "cloudflare";
            environmentFile = config.kix.secrets.cf-dns.path;
            group = "caddy";
          };
        };

        services.caddy.virtualHosts = lib.mkIf (cfg.domain != null) {
          ${cfg.domain} = {
            useACMEHost = cfg.domain;
            extraConfig = ''
              @auth header Authorization "Bearer {$RELAY_TOKEN}"
              handle @auth {
                reverse_proxy https://{header.X-Target-Host} {
                  header_up Host {header.X-Target-Host}
                }
              }
              respond 401
            '';
          };
        };
      };
    };
}
