{ ... }:
{
  flake.modules.nixos.mastodon =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.mastodon;
      domain = cfg.extraConfig.WEB_DOMAIN or cfg.localDomain;
    in
    {
      meta.maintainers = [ "ocfox" ];

      config = lib.mkIf cfg.enable {
        kix.secrets.mastodon-smtp = {
          mode = "640";
          owner = "mastodon";
        };

        security.acme.certs.${domain} = {
          dnsProvider = "cloudflare";
          environmentFile = config.kix.secrets.cf-dns.path;
          group = "mastodon";
        };

        services.caddy.virtualHosts.${domain} = {
          useACMEHost = domain;
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

        users.users.caddy.extraGroups = [ "mastodon" ];
      };
    };
}
