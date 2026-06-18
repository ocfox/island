{ self, inputs, ... }:
{
  hosts.kumo = {
    system = "x86_64-linux";
    stateVersion = "25.11";
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINGFOQAUa4fQiCbnD0lAoXI4HoYriPhCLAk/qOLS8IIC root@kumo";
    module =
      { config, pkgs, ... }:
      {
        imports = with self.modules.nixos; [ vps disko ];

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
        users.users.caddy.extraGroups = [ "acme" "mastodon" ];

        kix.secrets.grafana-secret-key.owner = "grafana";
        kix.secrets.grafana-admin.owner = "grafana";

        services.victoriametrics = {
          enable = true;
          listenAddress = "127.0.0.1:9090";
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
        };

        systemd.services.grafana.serviceConfig.EnvironmentFile =
          config.kix.secrets.grafana-admin.path;

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
