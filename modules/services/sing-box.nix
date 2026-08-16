{ ... }:
{
  flake.modules.nixos.sing-box =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.sing-box;
      singboxNft = pkgs.writeText "singbox.nft" ''
        table inet singbox {
          chain prerouting {
            type filter hook prerouting priority mangle; policy accept;
            iif "lo" meta mark != 0x1 accept
            meta l4proto { tcp, udp } meta mark 0x1 tproxy to :7895 accept
          }
          chain output {
            type route hook output priority mangle; policy accept;
            # Bypass self-traffic from sing-box outbounds (configured with routing_mark = 255 / 0xff) to prevent loops
            meta mark 0xff accept
            # Bypass Tailscale traffic
            oifname "tailscale0" accept
            # Intercept port 53 DNS queries to prevent GFW DNS poisoning
            udp dport 53 meta mark set 0x1
            tcp dport 53 meta mark set 0x1
            # Bypass private, local, and Tailscale networks
            ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 224.0.0.0/4, 255.255.255.255/32 } accept
            ip6 daddr { ::1/128, fc00::/7, fe80::/10, ff00::/8, fd7a:115c:a1e0::/48 } accept
            # Mark all other outbound TCP and UDP traffic for TPROXY interception
            meta l4proto { tcp, udp } meta mark set 0x1
          }
        }
      '';
    in
    {
      meta.maintainers = [ "ocfox" ];
      disabledModules = [ "services/networking/sing-box.nix" ];

      options.services.sing-box.enable = lib.mkEnableOption "sing-box transparent proxy";

      config = lib.mkIf cfg.enable {
        kix.secrets.sing-box.mode = "640";

        networking.nftables.enable = true;

        systemd.network.networks."10-tproxy" = {
          matchConfig.Name = "lo";
          routes = [
            {
              Destination = "0.0.0.0/0";
              Type = "local";
              Table = 100;
            }
            {
              Destination = "::/0";
              Type = "local";
              Table = 100;
            }
          ];
          routingPolicyRules = [
            {
              Family = "both";
              FirewallMark = 1;
              Table = 100;
            }
          ];
        };

        users.users.sing-box = {
          isSystemUser = true;
          group = "sing-box";
        };
        users.groups.sing-box = { };

        systemd.services.sing-box = {
          description = "sing-box transparent proxy";
          unitConfig.ConditionPathExists = "/var/lib/sing-box/config.json";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            User = "sing-box";
            Group = "sing-box";
            ExecStartPre = [
              "+${pkgs.nftables}/bin/nft -f ${singboxNft}"
            ];
            ExecStart = "${pkgs.local.sing-box}/bin/sing-box run -c /var/lib/sing-box/config.json -D /var/lib/sing-box";
            ExecStopPost = [
              "+-${pkgs.nftables}/bin/nft delete table inet singbox"
            ];
            Restart = "always";
            RestartSec = "3s";
            TimeoutStopSec = "5s";
            StateDirectory = "sing-box";
            AmbientCapabilities = [
              "CAP_NET_ADMIN"
              "CAP_NET_BIND_SERVICE"
              "CAP_NET_RAW"
            ];
            CapabilityBoundingSet = [
              "CAP_NET_ADMIN"
              "CAP_NET_BIND_SERVICE"
              "CAP_NET_RAW"
            ];
          };
        };

        systemd.services.sing-box-sync = {
          description = "Sync sing-box config from aptor";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          path = with pkgs; [
            curl
            coreutils
            systemd
            local.sing-box
          ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "sing-box-sync" ''
              mkdir -p /var/lib/sing-box
              KEY=$(tr -d ' \n\r' < ${config.kix.secrets.sing-box.path})
              if [ -n "$KEY" ]; then
                if curl --connect-timeout 5 --max-time 15 -fsSL "https://aptor.s4r.in/tproxy/$KEY" -o /var/lib/sing-box/config.json.tmp; then
                  if sing-box check -c /var/lib/sing-box/config.json.tmp; then
                    mv /var/lib/sing-box/config.json.tmp /var/lib/sing-box/config.json
                    chown -R sing-box:sing-box /var/lib/sing-box
                    chmod 644 /var/lib/sing-box/config.json
                    systemctl try-restart sing-box.service || true
                  fi
                fi
              fi
            '';
          };
        };

        systemd.timers.sing-box-sync = {
          description = "Daily sync sing-box config from aptor";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
          };
        };
      };
    };
}
