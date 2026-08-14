{ ... }:
{
  flake.modules.nixos.memos =
    { config, lib, ... }:
    let
      cfg = config.services.memos;
    in
    {
      meta.maintainers = [ "ocfox" ];

      options.services.memos = {
        domain = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "m.s4r.in";
          description = "Domain name for Memos ingress and ACME certificate";
        };
      };

      config = lib.mkIf cfg.enable {
        services.memos.settings = {
          MEMOS_MODE = "prod";
          MEMOS_ADDR = "127.0.0.1";
          MEMOS_PORT = "5230";
          MEMOS_DATA = "/var/lib/memos/";
          MEMOS_DRIVER = "sqlite";
          MEMOS_INSTANCE_URL = lib.mkIf (cfg.domain != null) "https://${cfg.domain}";
        };

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
              reverse_proxy 127.0.0.1:5230
            '';
          };
        };
      };
    };
}
