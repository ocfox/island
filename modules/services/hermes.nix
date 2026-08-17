{ ... }:
{
  flake.modules.nixos.hermes =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.hermes;
    in
    {
      meta.maintainers = [ "ocfox" ];

      options.services.hermes = {
        enable = lib.mkEnableOption "Nous Hermes Agent in Podman container";

        image = lib.mkOption {
          type = lib.types.str;
          default = "docker.io/nousresearch/hermes-agent:latest";
          description = "OCI image for Nous Hermes Agent";
        };

        dataDir = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/hermes";
          description = "Host directory for Hermes persistent data and configuration (/opt/data)";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 9119;
          description = "Dashboard Web UI port";
        };

        gatewayPort = lib.mkOption {
          type = lib.types.port;
          default = 8642;
          description = "Gateway API port";
        };

        listenAddr = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Host listen address for mapped container ports";
        };

        domain = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "hermes.s4r.in";
          description = "Domain name for Hermes Dashboard ingress and ACME certificate via Caddy";
        };

        environmentFiles = lib.mkOption {
          type = lib.types.listOf lib.types.path;
          default = [ ];
          description = "List of environment files with secrets to pass to container";
        };

        extraEnvironment = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Extra environment variables passed to Hermes container";
        };
      };

      config = lib.mkIf cfg.enable {
        virtualisation.podman.enable = true;
        virtualisation.oci-containers.backend = "podman";

        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 root root -"
        ];

        virtualisation.oci-containers.containers.hermes = {
          image = cfg.image;
          cmd = [ "gateway" "run" ];
          autoStart = true;
          extraOptions = [ "--network=host" ];
          volumes = [
            "${cfg.dataDir}:/opt/data"
          ];
          environmentFiles = cfg.environmentFiles;
          environment = {
            HERMES_HOME = "/opt/data";
            HERMES_DASHBOARD = "true";
            HERMES_DASHBOARD_HOST = "127.0.0.1";
            HERMES_DASHBOARD_PORT = toString cfg.port;
            API_SERVER_HOST = "127.0.0.1";
            API_SERVER_PORT = toString cfg.gatewayPort;
          } // cfg.extraEnvironment;
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
              reverse_proxy ${cfg.listenAddr}:${toString cfg.port} {
                header_up Host ${cfg.listenAddr}
              }
            '';
          };
        };
      };
    };
}
