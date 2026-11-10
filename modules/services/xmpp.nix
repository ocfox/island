{ ... }:
{
  flake.modules.nixos.xmpp =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.xmpp;
      domain = cfg.domain; # s4r.in
      edgeDomain = "xm.${domain}"; # xm.s4r.in

      asciiCat = ''
 ／|、
(˙、．7
 |、～ヽ
 じしf_,)ノ

Hi, here is sarin's xmpp node.
'';
    in
    {
      meta.maintainers = [ "ocfox" ];

      options.services.xmpp = {
        enable = lib.mkEnableOption "XMPP service (Prosody)";

        domain = lib.mkOption {
          type = lib.types.str;
          default = "s4r.in";
          description = "Primary JID domain name for XMPP server (e.g. ib@s4r.in)";
        };

        adminJid = lib.mkOption {
          type = lib.types.str;
          default = "ib@s4r.in";
          description = "Admin JID for Prosody";
        };
      };

      config = lib.mkIf cfg.enable {
        # ACME certificate covering only the necessary domains: xm.s4r.in and s4r.in
        security.acme.certs.${edgeDomain} = {
          dnsProvider = "cloudflare";
          environmentFile = config.kix.secrets.cf-dns.path;
          dnsPropagationCheck = false; # Cloudflare updates instantly; bypass local systemd-resolved NXDOMAIN caching
          extraDomainNames = [ domain ];
          group = "caddy";
          reloadServices = [ "prosody.service" ];
        };

        # Allow prosody to read the ACME certificates in /var/lib/acme
        users.users.prosody.extraGroups = [ "caddy" ];

        # Prosody server configuration
        services.prosody = {
          enable = true;
          admins = [ cfg.adminJid ];
          allowRegistration = false; # Private server; accounts created via prosodyctl
          c2sRequireEncryption = true;
          s2sRequireEncryption = true;
          xmppComplianceSuite = false; # Don't force MUC

          # Bind HTTP internally for Caddy reverse proxy
          httpInterfaces = [
            "127.0.0.1"
            "::1"
          ];
          httpPorts = [ 5280 ];

          modules = {
            roster = true;
            saslauth = true;
            tls = true;
            dialback = true;
            disco = true;
            carbons = true;
            csi = true;
            cloud_notify = true;
            pep = true;
            private = true;
            blocklist = true;
            vcard_legacy = true;
            bookmarks = true;
            version = true;
            uptime = true;
            time = true;
            ping = true;
            register = false;
            mam = true;
            smacks = true;
            admin_adhoc = true;
            motd = true;
            bosh = true;
            websocket = true;
          };

          extraModules = [
            "http_altconnect" # RFC 7395 / XEP-0156 discovery via /.well-known/host-meta
          ];

          # Easter Eggs & Server Branding
          extraConfig = ''
            os_version_command = "echo 'NixOS (kumo in the clouds ☁️)'"

            motd_text = [[✦ Welcome back to island, ib.
All systems nominal. Soft breeze drifting across kumo. ☁️]]
          '';

          httpFileShare = {
            domain = "upload.${edgeDomain}";
            http_host = edgeDomain;
            http_external_url = "https://${edgeDomain}/upload/";
            size_limit = 50 * 1024 * 1024; # 50 MB per file
            expires_after = "30 days";
            daily_quota = 500 * 1024 * 1024; # 500 MB per day
          };

          virtualHosts = {
            # Primary JID domain: ib@s4r.in
            ${domain} = {
              domain = domain;
              enabled = true;
              ssl = {
                key = "/var/lib/acme/${edgeDomain}/key.pem";
                cert = "/var/lib/acme/${edgeDomain}/fullchain.pem";
              };
            };

            # Edge host: user@xm.s4r.in
            ${edgeDomain} = {
              domain = edgeDomain;
              enabled = true;
              ssl = {
                key = "/var/lib/acme/${edgeDomain}/key.pem";
                cert = "/var/lib/acme/${edgeDomain}/fullchain.pem";
              };
            };
          };
        };

        # Ensure ACME selfsigned exists before Prosody starts
        systemd.services.prosody = {
          after = [
            "acme-selfsigned-${edgeDomain}.service"
            "acme-${edgeDomain}.service"
          ];
          wants = [
            "acme-selfsigned-${edgeDomain}.service"
          ];
        };

        # Caddy reverse proxy for Web (xm.s4r.in), WebSocket, and HTTP Upload
        services.caddy.virtualHosts.${edgeDomain} = {
          useACMEHost = edgeDomain;
          extraConfig = ''
            handle /xmpp-websocket {
              reverse_proxy 127.0.0.1:5280
            }

            handle /http-bind* {
              reverse_proxy 127.0.0.1:5280
            }

            handle /upload* {
              reverse_proxy 127.0.0.1:5280
            }

            handle /.well-known/host-meta* {
              reverse_proxy 127.0.0.1:5280
            }

            handle {
              header Content-Type "text/plain; charset=utf-8"
              respond `${asciiCat}`
            }
          '';
        };
      };
    };
}
