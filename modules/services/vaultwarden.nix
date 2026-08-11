{ ... }:
{
  flake.modules.nixos.vaultwarden =
    { config, lib, ... }:
    let
      cfg = config.services.vaultwarden;
      domain = "vault.s4r.in";
    in
    {
      meta.maintainers = [ "ocfox" ];

      config = lib.mkIf cfg.enable {
        kix.secrets.vault.mode = "640";

        services.vaultwarden = {
          config = {
            SMTP_SECURITY = "starttls";
            SMTP_PORT = 587;
            SMTP_HOST = "smtp.migadu.com";
            SMTP_FROM = "vault@s4r.in";
            SMTP_USERNAME = "vault@s4r.in";
            DOMAIN = "https://${domain}";
          };
          environmentFile = config.kix.secrets.vault.path;
        };

        security.acme.certs.${domain} = {
          dnsProvider = "cloudflare";
          environmentFile = config.kix.secrets.cf-dns.path;
          group = "caddy";
        };

        services.caddy.virtualHosts.${domain} = {
          useACMEHost = domain;
          extraConfig = ''
            reverse_proxy localhost:8000 {
              header_up X-Real-IP {remote_host}
            }
          '';
        };
      };
    };
}
