{ self, inputs, ... }:
{
  hosts.kumo = {
    system = "x86_64-linux";
    stateVersion = "25.11";
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINGFOQAUa4fQiCbnD0lAoXI4HoYriPhCLAk/qOLS8IIC root@kumo";
    module =
      { config, lib, pkgs, ... }:
      {
        imports = with self.modules.nixos; [
          vps
          disko
        ];

        networking.nftables.ruleset = ''
          table inet filter {
            chain input {
              type filter hook input priority filter; policy drop;

              iif lo accept
              ct state { established, related } accept
              ct state invalid drop

              ip6 nexthdr icmpv6 icmpv6 type {
                echo-request,
                nd-neighbor-solicit,
                nd-neighbor-advert,
                nd-router-advert,
                mld-listener-query,
              } accept

              tcp dport 22 accept
              tcp dport { 80, 443 } accept
              udp dport 443 accept

              # allow aqua agent (gallery) to push metrics to VictoriaMetrics
              ip saddr 100.64.0.1 tcp dport 9090 accept
            }

            chain forward {
              type filter hook forward priority filter; policy drop;
            }

            chain output {
              type filter hook output priority filter; policy accept;
            }
          }
        '';

        systemd.network.networks."10-eth0" = {
          address = [
            "2401:b60:e0fd:11::2/64"
            "2401:b60:e0fd:151::2/64"
            "2401:b60:e0fd:3d::2/64"
            "2401:b60:e0fd:2b::2/64"
          ];
          networkConfig = {
            DHCP = "no";
            IPv6AcceptRA = false;
          };
          routes = [ { Gateway = "2401:b60:e0fd:2b::1"; } ];
        };
        kix.secrets.vault.mode = "640";
        kix.secrets.cf-dns.mode = "640";
        kix.secrets.restic-b2.mode = "640";
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
        # Offsite backup to Backblaze B2 via its S3-compatible API (free tier).
        # Backs up memos + vaultwarden data and a logical dump of the mastodon
        # Postgres DB. Mastodon media (mostly cached remote files, auto-refetched)
        # is intentionally excluded. The restic-b2 secret must contain
        # AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and RESTIC_PASSWORD.
        services.restic.backups.b2 = {
          initialize = true;
          # S3 path uses the bucket NAME (not the bucket id).
          repository = "s3:https://s3.us-west-004.backblazeb2.com/kumoback";
          environmentFile = config.kix.secrets.restic-b2.path;
          paths = [
            "/var/lib/memos"
            "/var/lib/vaultwarden"
            "/var/backup/postgres"
          ];
          backupPrepareCommand = ''
            install -d -m 0700 /var/backup/postgres
            ${pkgs.util-linux}/bin/runuser -u postgres -- \
              ${config.services.postgresql.package}/bin/pg_dump -Fc mastodon \
              -f /var/backup/postgres/mastodon.dump
          '';
          backupCleanupCommand = ''
            rm -f /var/backup/postgres/mastodon.dump
          '';
          timerConfig = {
            OnCalendar = "daily";
            RandomizedDelaySec = "1h";
            Persistent = true;
          };
          pruneOpts = [
            "--keep-daily 7"
            "--keep-weekly 4"
            "--keep-monthly 6"
          ];
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

        kix.secrets.grafana-secret-key.owner = "grafana";
        kix.secrets.grafana-admin.owner = "grafana";

        services.victoriametrics = {
          enable = true;
          listenAddress = "0.0.0.0:9090";
          retentionPeriod = "60d";
        };

        services.vmagent = {
          enable = true;
          remoteWrite.url = "http://127.0.0.1:9090/api/v1/write";
          prometheusConfig.scrape_configs = [
            {
              job_name = "node";
              static_configs = [ { targets = [ "127.0.0.1:9100" ]; } ];
            }
            {
              job_name = "systemd";
              static_configs = [ { targets = [ "127.0.0.1:9558" ]; } ];
            }
            {
              job_name = "postgres";
              static_configs = [ { targets = [ "127.0.0.1:9187" ]; } ];
            }
            {
              job_name = "caddy";
              static_configs = [ { targets = [ "127.0.0.1:2019" ]; } ];
            }
            {
              job_name = "aqua";
              static_configs = [ { targets = [ "100.64.0.1:8765" ]; } ];
              metrics_path = "/metrics";
            }
          ];
        };

        services.postgresql.settings = {
          shared_preload_libraries = "pg_stat_statements";
        };

        services.prometheus.exporters = {
          node = {
            enable = true;
            listenAddress = "127.0.0.1";
          };
          systemd = {
            enable = true;
            listenAddress = "127.0.0.1";
          };
          postgres = {
            enable = true;
            listenAddress = "127.0.0.1";
            runAsLocalSuperUser = true;
          };
        };

        services.caddy.globalConfig = "metrics";

        services.grafana = {
          enable = true;
          settings = {
            server = {
              http_addr = "127.0.0.1";
              http_port = 3000;
              domain = "g.s4r.in";
              root_url = "https://g.s4r.in/";
            };
            security.secret_key = "$__file{${config.kix.secrets.grafana-secret-key.path}}";
            feature_toggles.dashboardNewLayouts = true;
          };
          provision.datasources.settings.datasources = [
            {
              name = "VictoriaMetrics";
              type = "prometheus";
              url = "http://127.0.0.1:9090";
              isDefault = true;
            }
          ];
          provision.dashboards.settings.providers = [
            {
              name = "Aqua";
              type = "file";
              updateIntervalSeconds = 30;
              allowUiUpdates = true;
              options.path = pkgs.runCommand "aqua-dashboards" { } ''
                mkdir $out
                cp ${./aqua-dashboard.json} $out/aqua.json
              '';
            }
          ];
        };

        systemd.services.grafana.serviceConfig.EnvironmentFile = config.kix.secrets.grafana-admin.path;

        security.acme.certs."g.s4r.in" = {
          dnsProvider = "cloudflare";
          environmentFile = config.kix.secrets.cf-dns.path;
          group = "caddy";
        };

        services.caddy.virtualHosts."g.s4r.in" = {
          useACMEHost = "g.s4r.in";
          extraConfig = ''
            reverse_proxy 127.0.0.1:3000
          '';
        };
      };
  };
}
