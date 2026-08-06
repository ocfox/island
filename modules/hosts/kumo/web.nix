{
  flake.modules.nixos.kumo =
    { config, pkgs, ... }:
    {
      kix.secrets.vault.mode = "640";
      kix.secrets.cf-dns.mode = "640";
      kix.secrets.mastodon-smtp = {
        mode = "640";
        owner = "mastodon";
      };

      security.acme = {
        acceptTerms = true;
        defaults.email = "civet@ocfox.me";
        certs."vault.s4r.in" = {
          dnsProvider = "cloudflare";
          environmentFile = config.kix.secrets.cf-dns.path;
          group = "caddy";
        };
        certs."m.s4r.in" = {
          dnsProvider = "cloudflare";
          environmentFile = config.kix.secrets.cf-dns.path;
          group = "caddy";
        };
        certs."exec.s4r.in" = {
          dnsProvider = "cloudflare";
          environmentFile = config.kix.secrets.cf-dns.path;
          group = "caddy";
        };
        certs."mastodon.ocfox.me" = {
          dnsProvider = "cloudflare";
          environmentFile = config.kix.secrets.cf-dns.path;
          group = "mastodon";
        };
      };
      services.vaultwarden = {
        enable = true;
        config = {
          SMTP_SECURITY = "starttls";
          SMTP_PORT = 587;
          SMTP_HOST = "smtp.migadu.com";
          SMTP_FROM = "vault@s4r.in";
          SMTP_USERNAME = "vault@s4r.in";
          DOMAIN = "https://vault.s4r.in";
        };
        environmentFile = config.kix.secrets.vault.path;
      };
      services.mastodon = {
        enable = true;
        localDomain = "ocfox.me";
        configureNginx = false;
        streamingProcesses = 1;
        smtp = {
          host = "smtp.migadu.com";
          port = 587;
          user = "mastodon@ocfox.me";
          fromAddress = "mastodon@ocfox.me";
          passwordFile = config.kix.secrets.mastodon-smtp.path;
        };
        extraConfig.WEB_DOMAIN = "mastodon.ocfox.me";
        extraConfig.SINGLE_USER_MODE = "true";
      };
      services.memos = {
        enable = true;
        settings = {
          MEMOS_MODE = "prod";
          MEMOS_ADDR = "127.0.0.1";
          MEMOS_PORT = "5230";
          MEMOS_DATA = "/var/lib/memos/";
          MEMOS_DRIVER = "sqlite";
          MEMOS_INSTANCE_URL = "https://m.s4r.in";
        };
      };
      services.caddy = {
        enable = true;
        virtualHosts."vault.s4r.in" = {
          useACMEHost = "vault.s4r.in";
          extraConfig = ''
            reverse_proxy localhost:8000 {
              header_up X-Real-IP {remote_host}
            }
          '';
        };
        virtualHosts."m.s4r.in" = {
          useACMEHost = "m.s4r.in";
          extraConfig = ''
            reverse_proxy 127.0.0.1:5230
          '';
        };
        virtualHosts."exec.s4r.in" = {
          useACMEHost = "exec.s4r.in";
          extraConfig = ''
            reverse_proxy 127.0.0.1:${toString config.services.sandbox-runner.listenPort}
          '';
        };
        virtualHosts."mastodon.ocfox.me" = {
          useACMEHost = "mastodon.ocfox.me";
          extraConfig = ''
            handle_path /system/* {
              file_server * {
                root /var/lib/mastodon/public-system
              }
            }

            handle /api/v1/streaming/* {
              reverse_proxy unix//run/mastodon-streaming/streaming-1.socket
            }

            route * {
              file_server * {
                root ${pkgs.mastodon}/public
                pass_thru
              }
              reverse_proxy * unix//run/mastodon-web/web.socket
            }

            handle_errors {
              root * ${pkgs.mastodon}/public
              rewrite 500.html
              file_server
            }

            encode gzip

            header /* {
              Strict-Transport-Security "max-age=31536000;"
            }
            header /emoji/* Cache-Control "public, max-age=31536000, immutable"
            header /packs/* Cache-Control "public, max-age=31536000, immutable"
            header /system/accounts/avatars/* Cache-Control "public, max-age=31536000, immutable"
            header /system/media_attachments/files/* Cache-Control "public, max-age=31536000, immutable"
          '';
        };
      };
      users.users.caddy.extraGroups = [
        "acme"
        "mastodon"
      ];
    };
}
