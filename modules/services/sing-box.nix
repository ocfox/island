{ ... }:
{
  flake.modules.nixos.sing-box =
    {
      config,
      lib,
      pkgs,
      options,
      ...
    }:
    let
      cfg = config.services.sing-box;
    in
    {
      meta.maintainers = [ "ocfox" ];

      disabledModules = [ "services/networking/sing-box.nix" ];

      options.services.sing-box = {
        enable = lib.mkEnableOption "sing-box client service";

        package = lib.mkPackageOption pkgs.local "sing-box" { };

        hubUrl = lib.mkOption {
          type = lib.types.str;
          default = "https://aptor.s4r.in";
          description = "Base URL of aptor subscription hub";
        };

        mode = lib.mkOption {
          type = lib.types.enum [
            "tproxy"
            "tun"
          ];
          default = "tproxy";
          description = "Inbound mode to request from aptor (tproxy or tun)";
        };

        secretName = lib.mkOption {
          type = lib.types.str;
          default = "sing-box";
          description = "Name of kix secret containing the aptor secret key";
        };
      };

      config = lib.mkIf cfg.enable (
        lib.optionalAttrs (options ? systemd) {
          kix.secrets.${cfg.secretName}.mode = "640";

          systemd.services.sing-box = {
            description = "sing-box client service";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            path = [
              pkgs.curl
              pkgs.coreutils
              cfg.package
            ];
            preStart = ''
              mkdir -p /var/lib/sing-box
              KEY="$(cat ${config.kix.secrets.${cfg.secretName}.path} | tr -d ' \n\r')"
              if [ -n "$KEY" ]; then
                if curl -fsSL "${cfg.hubUrl}/${cfg.mode}/$KEY" -o /var/lib/sing-box/config.json.tmp; then
                  if ${cfg.package}/bin/sing-box check -c /var/lib/sing-box/config.json.tmp; then
                    mv /var/lib/sing-box/config.json.tmp /var/lib/sing-box/config.json
                  fi
                fi
              fi
              if [ ! -f /var/lib/sing-box/config.json ]; then
                echo "Error: No sing-box config available at /var/lib/sing-box/config.json" >&2
                exit 1
              fi
            '';
            serviceConfig = {
              Type = "simple";
              ExecStart = "${cfg.package}/bin/sing-box run -c /var/lib/sing-box/config.json -D /var/lib/sing-box";
              Restart = "always";
              RestartSec = "3s";
              StateDirectory = "sing-box";
              CapabilityBoundingSet = [
                "CAP_NET_ADMIN"
                "CAP_NET_BIND_SERVICE"
                "CAP_NET_RAW"
              ];
              AmbientCapabilities = [
                "CAP_NET_ADMIN"
                "CAP_NET_BIND_SERVICE"
                "CAP_NET_RAW"
              ];
            };
          };
        }
      );
    };
}
