{ ... }:
{
  flake.modules.nixos.hysteria =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.hysteria;
      hysteriaNft = pkgs.writeText "hysteria.nft" ''
        table inet hysteria {
          chain prerouting {
            type nat hook prerouting priority dstnat; policy accept;
            udp dport ${toString cfg.portRange.from}-${toString cfg.portRange.to} redirect to :${toString cfg.listenPort}
          }
        }
      '';
    in
    {
      meta.maintainers = [ "ocfox" ];

      options.services.hysteria = {
        enable = lib.mkEnableOption "Hysteria 2 server";

        package = lib.mkPackageOption pkgs "hysteria" { };

        listenPort = lib.mkOption {
          type = lib.types.port;
          default = 40000;
          description = "Main UDP listening port for Hysteria 2";
        };

        portRange = {
          from = lib.mkOption {
            type = lib.types.port;
            default = 30000;
            description = "Start of the port hopping range";
          };
          to = lib.mkOption {
            type = lib.types.port;
            default = 40000;
            description = "End of the port hopping range";
          };
        };

        secretName = lib.mkOption {
          type = lib.types.str;
          description = "Name of the kix secret containing the Hysteria 2 configuration YAML";
        };
      };

      config = lib.mkIf cfg.enable {
        kix.secrets.${cfg.secretName} = {
          mode = "640";
          owner = "hysteria";
          group = "hysteria";
        };

        networking.nftables.enable = true;

        users.users.hysteria = {
          isSystemUser = true;
          group = "hysteria";
        };
        users.groups.hysteria = { };

        systemd.services.hysteria = {
          description = "Hysteria 2 server";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            User = "hysteria";
            Group = "hysteria";
            StateDirectory = "hysteria";
            WorkingDirectory = "/var/lib/hysteria";
            Restart = "always";
            RestartSec = "3s";

            # Generate self-signed certificate if not present
            ExecStartPre = [
              (pkgs.writeShellScript "hysteria-cert-gen" ''
                if [ ! -f /var/lib/hysteria/server.crt ] || [ ! -f /var/lib/hysteria/server.key ]; then
                  ${pkgs.openssl}/bin/openssl req -x509 -nodes -newkey ec:<(${pkgs.openssl}/bin/openssl ecparam -name prime256v1) \
                    -keyout /var/lib/hysteria/server.key \
                    -out /var/lib/hysteria/server.crt \
                    -days 36500 \
                    -subj "/CN=bing.com"
                  chmod 600 /var/lib/hysteria/server.key /var/lib/hysteria/server.crt
                fi
              '')
              "+${pkgs.nftables}/bin/nft -f ${hysteriaNft}"
            ];

            ExecStart = "${cfg.package}/bin/hysteria server --config ${config.kix.secrets.${cfg.secretName}.path}";

            ExecStopPost = [
              "+-${pkgs.nftables}/bin/nft delete table inet hysteria"
            ];

            AmbientCapabilities = [
              "CAP_NET_ADMIN"
              "CAP_NET_BIND_SERVICE"
            ];
            CapabilityBoundingSet = [
              "CAP_NET_ADMIN"
              "CAP_NET_BIND_SERVICE"
            ];
          };
        };
      };
    };
}
