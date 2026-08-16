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
    in
    {
      meta.maintainers = [ "ocfox" ];
      disabledModules = [ "services/networking/sing-box.nix" ];

      options.services.sing-box.enable = lib.mkEnableOption "sing-box transparent proxy";

      config = lib.mkIf cfg.enable {
        kix.secrets.sing-box.mode = "640";

        networking.nftables.enable = true;
        networking.nftables.tables.singbox = {
          family = "inet";
          content = ''
            chain prerouting {
              type filter hook prerouting priority mangle; policy accept;
              iif "lo" meta mark != 0x1 accept
              meta mark 0x1 tproxy to :7895 accept
            }
            chain output {
              type route hook output priority mangle; policy accept;
              meta mark 0xff accept
              ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255/32 } accept
              ip6 daddr { ::1/128, fc00::/7, fe80::/10, ff00::/8 } accept
              meta l4proto { tcp, udp } meta mark set 0x1
            }
          '';
        };

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
              FirewallMark = 1;
              Table = 100;
            }
          ];
        };

        systemd.services.sing-box = {
          description = "sing-box transparent proxy";
          after = [
            "network.target"
            "sing-box-sync.service"
          ];
          wants = [ "sing-box-sync.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStart = "${pkgs.local.sing-box}/bin/sing-box run -c /var/lib/sing-box/config.json -D /var/lib/sing-box";
            Restart = "always";
            RestartSec = "3s";
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
                if curl -fsSL "https://aptor.s4r.in/tproxy/$KEY" -o /var/lib/sing-box/config.json.tmp; then
                  if sing-box check -c /var/lib/sing-box/config.json.tmp; then
                    mv /var/lib/sing-box/config.json.tmp /var/lib/sing-box/config.json
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
