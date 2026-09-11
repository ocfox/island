{ ... }:
{
  flake.modules.nixos.ntfy =
    { config, lib, pkgs, ... }:
    let
      cfg = config.services.ntfy;
      domain = cfg.domain;
    in
    {
      meta.maintainers = [ "ocfox" ];

      options.services.ntfy = {
        enable = lib.mkEnableOption "ntfy notification service";

        domain = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "ntfy.s4r.in";
          description = "Domain name for ntfy ingress and ACME certificate";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 2586;
          description = "Host listen port for ntfy";
        };
      };

      config = lib.mkIf cfg.enable {
        services.ntfy-sh = {
          enable = true;
          settings = {
            base-url = lib.mkIf (cfg.domain != null) "https://${cfg.domain}";
            listen-http = "127.0.0.1:${toString cfg.port}";
            behind-proxy = true;
            auth-default-access = "deny-all";
            upstream-base-url = "https://ntfy.sh";
          };
        };

        systemd.services.ntfy-sh.postStart = ''
          # Grant everyone write-only to notification topics so local systemd scripts and CI can publish without auth
          ${pkgs.ntfy-sh}/bin/ntfy access everyone "backup" write-only || true
          ${pkgs.ntfy-sh}/bin/ntfy access everyone "system" write-only || true
          ${pkgs.ntfy-sh}/bin/ntfy access everyone "ci" write-only || true
        '';

        systemd.services."notify-failure@" = {
          description = "Send service failure alert to ntfy for %i";
          serviceConfig.Type = "oneshot";
          script = ''
            ${pkgs.curl}/bin/curl -s -m 5 \
              -H 'Title: Service Failure' \
              -H 'Priority: high' \
              -H 'Tags: warning' \
              -d "Service %i failed on %H" \
              http://127.0.0.1:${toString cfg.port}/system || true
          '';
        };

        security.acme.certs = lib.mkIf (cfg.domain != null) {
          ${domain} = {
            dnsProvider = "cloudflare";
            environmentFile = config.kix.secrets.cf-dns.path;
            group = "caddy";
          };
        };

        services.caddy.virtualHosts = lib.mkIf (cfg.domain != null) {
          ${domain} = {
            useACMEHost = domain;
            extraConfig = ''
              reverse_proxy 127.0.0.1:${toString cfg.port}
            '';
          };
        };
      };
    };
}
