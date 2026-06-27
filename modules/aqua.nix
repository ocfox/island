{ ... }:
{
  flake.modules.nixos.aqua =
    { config, lib, pkgs, ... }:
    let
      cfg = config.services.aqua;
      postgresDatasource = {
        type = "postgres";
        uid = "aqua-postgres";
      };
      dashboardDir = pkgs.writeTextDir "aqua-window-dashboard.json" (
        builtins.toJSON {
          uid = "aqua-window";
          title = "Aqua Windows";
          tags = [
            "aqua"
            "windows"
          ];
          timezone = "browser";
          schemaVersion = 41;
          version = 1;
          refresh = "5m";
          time = {
            from = "now-24h";
            to = "now";
          };
          templating.list = [
            {
              name = "agent";
              type = "query";
              datasource = postgresDatasource;
              refresh = 1;
              includeAll = true;
              allValue = "__all";
              multi = true;
              query = "select distinct entity as __text, entity as __value from aqua_timeline order by 1";
              current = {
                selected = true;
                text = [ "All" ];
                value = [ "$__all" ];
              };
            }
          ];
          panels = [
            {
              id = 1;
              type = "state-timeline";
              title = "Window timeline";
              datasource = postgresDatasource;
              gridPos = {
                x = 0;
                y = 0;
                w = 24;
                h = 9;
              };
              targets = [
                {
                  refId = "A";
                  datasource = postgresDatasource;
                  format = "table";
                  rawQuery = true;
                  rawSql = ''
                    select
                      time as "time",
                      time_end as "timeend",
                      coalesce(workspace, $$$$) || $q$ / $q$ || state as "metric",
                      coalesce(title, $$$$) as "title"
                    from aqua_timeline
                    where kind = 'focus'
                      and $__timeFilter(time)
                      and ($q$''${agent:raw}$q$ = $q$__all$q$ or entity in (''${agent:singlequote}))
                    order by time
                  '';
                }
              ];
              options = {
                mergeValues = false;
                showValue = "always";
                tooltip.mode = "single";
                legend = {
                  showLegend = true;
                  displayMode = "list";
                  placement = "bottom";
                };
              };
              fieldConfig = {
                defaults.custom = {
                  fillOpacity = 70;
                  lineWidth = 0;
                  spanNulls = false;
                };
                overrides = [ ];
              };
            }
            {
              id = 2;
              type = "timeseries";
              title = "Focused hours by hour";
              datasource = postgresDatasource;
              gridPos = {
                x = 0;
                y = 9;
                w = 12;
                h = 8;
              };
              targets = [
                {
                  refId = "A";
                  datasource = postgresDatasource;
                  format = "time_series";
                  rawQuery = true;
                  rawSql = ''
                    with bounds as (
                      select
                        $__timeFrom()::timestamptz as from_ts,
                        $__timeTo()::timestamptz as to_ts
                    ),
                    buckets as (
                      select generate_series(
                        date_trunc('hour', from_ts),
                        date_trunc('hour', to_ts),
                        interval '1 hour'
                      ) as bucket
                      from bounds
                    )
                    select
                      buckets.bucket as "time",
                      sum(
                        extract(epoch from
                          least(aqua_timeline.time_end, buckets.bucket + interval '1 hour')
                          - greatest(aqua_timeline.time, buckets.bucket)
                        )
                      ) / 3600.0 as "focused"
                    from buckets
                    left join aqua_timeline
                      on aqua_timeline.kind = 'focus'
                     and aqua_timeline.time < buckets.bucket + interval '1 hour'
                     and aqua_timeline.time_end > buckets.bucket
                     and ($q$''${agent:raw}$q$ = $q$__all$q$ or aqua_timeline.entity in (''${agent:singlequote}))
                    group by buckets.bucket
                    order by buckets.bucket
                  '';
                }
              ];
              fieldConfig = {
                defaults = {
                  unit = "h";
                  custom.drawStyle = "bars";
                };
                overrides = [ ];
              };
              options = {
                tooltip.mode = "single";
                legend.showLegend = false;
              };
            }
            {
              id = 3;
              type = "table";
              title = "Top applications";
              datasource = postgresDatasource;
              gridPos = {
                x = 12;
                y = 9;
                w = 12;
                h = 8;
              };
              targets = [
                {
                  refId = "A";
                  datasource = postgresDatasource;
                  format = "table";
                  rawQuery = true;
                  rawSql = ''
                    select
                      state as "application",
                      round(sum(
                        extract(epoch from
                          least(time_end, $__timeTo()::timestamptz)
                          - greatest(time, $__timeFrom()::timestamptz)
                        )
                      ) / 3600.0, 2) as "hours"
                    from aqua_timeline
                    where kind = 'focus'
                      and time < $__timeTo()::timestamptz
                      and time_end > $__timeFrom()::timestamptz
                      and ($q$''${agent:raw}$q$ = $q$__all$q$ or entity in (''${agent:singlequote}))
                    group by state
                    order by "hours" desc
                    limit 20
                  '';
                }
              ];
              options.showHeader = true;
              fieldConfig.defaults.custom.align = "auto";
            }
            {
              id = 4;
              type = "table";
              title = "Recent windows";
              datasource = postgresDatasource;
              gridPos = {
                x = 0;
                y = 17;
                w = 24;
                h = 8;
              };
              targets = [
                {
                  refId = "A";
                  datasource = postgresDatasource;
                  format = "table";
                  rawQuery = true;
                  rawSql = ''
                    select
                      time,
                      time_end,
                      entity as agent,
                      workspace,
                      state as application,
                      title
                    from aqua_timeline
                    where kind = 'focus'
                      and $__timeFilter(time)
                      and ($q$''${agent:raw}$q$ = $q$__all$q$ or entity in (''${agent:singlequote}))
                    order by time desc
                    limit 100
                  '';
                }
              ];
              options.showHeader = true;
            }
          ];
        }
      );
    in
    {
      options.services.aqua = {
        enable = lib.mkEnableOption "Aqua activity ingestion service";
        domain = lib.mkOption { type = lib.types.str; };
        tokenFile = lib.mkOption { type = lib.types.path; };
      };

      config = lib.mkIf cfg.enable {
        users.groups.aqua = { };
        users.users.aqua = {
          isSystemUser = true;
          group = "aqua";
        };

        services.postgresql.ensureDatabases = [ "aqua" ];
        services.postgresql.ensureUsers = [
          {
            name = "aqua";
            ensureDBOwnership = true;
          }
          { name = "grafana"; }
        ];

        systemd.services.aqua = {
          description = "Aqua activity ingestion service";
          after = [
            "network-online.target"
            "postgresql.service"
          ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            User = "aqua";
            Group = "aqua";
            ExecStartPre = "${pkgs.postgresql}/bin/psql --dbname=postgresql:///aqua?host=/run/postgresql --file=${pkgs.local.aqua.server}/share/aqua/migrations/001_initial.sql";
            ExecStart = "${pkgs.local.aqua.server}/bin/aqua-server";
            Environment = [
              "AQUA_TOKEN_FILE=${cfg.tokenFile}"
              "AQUA_DATABASE_URL=postgresql:///aqua?host=/run/postgresql"
            ];
            Restart = "on-failure";
            RestartSec = "2s";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
          };
        };

        services.caddy.virtualHosts.${cfg.domain} = {
          useACMEHost = cfg.domain;
          extraConfig = ''
            handle /v1/* {
              reverse_proxy 127.0.0.1:8765
            }

            respond "not found" 404
          '';
        };

        services.vmagent.prometheusConfig.scrape_configs = lib.mkAfter [
          {
            job_name = "aqua";
            static_configs = [ { targets = [ "127.0.0.1:8765" ]; } ];
            metrics_path = "/metrics";
          }
        ];

        services.grafana.provision.datasources.settings.datasources = lib.mkAfter [
          {
            name = "Aqua";
            type = "postgres";
            uid = "aqua-postgres";
            version = 2;
            url = "/run/postgresql";
            user = "grafana";
            database = "aqua";
            jsonData = {
              database = "aqua";
              sslmode = "disable";
              postgresVersion = 1700;
            };
          }
        ];

        services.grafana.provision.dashboards.settings = {
          apiVersion = 1;
          providers = lib.mkAfter [
            {
              name = "Aqua";
              type = "file";
              updateIntervalSeconds = 30;
              allowUiUpdates = true;
              options.path = dashboardDir;
            }
          ];
        };
      };
    };
}
