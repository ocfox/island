{ ... }:
{
  flake.modules.nixos.monitoring =
    {
      config,
      pkgs,
      lib,
      options,
      ...
    }:
    let
      cfg = config.services.monitoring-stack;
      domain = "g.s4r.in";
    in
    {
      meta.maintainers = [ "ocfox" ];

      options.services.monitoring-stack = {
        enable = lib.mkEnableOption "monitoring stack (VictoriaMetrics + Grafana + vmagent + exporters)";
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
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
                  domain = domain;
                  root_url = "https://${domain}/";
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

            security.acme.certs.${domain} = {
              dnsProvider = "cloudflare";
              environmentFile = config.kix.secrets.cf-dns.path;
              group = "caddy";
            };

            services.caddy.virtualHosts.${domain} = {
              useACMEHost = domain;
              extraConfig = ''
                reverse_proxy 127.0.0.1:3000
              '';
            };
          }

          (lib.optionalAttrs (options ? systemd) {
            systemd.services.grafana.serviceConfig.EnvironmentFile = config.kix.secrets.grafana-admin.path;
          })
        ]
      );
    };
}
