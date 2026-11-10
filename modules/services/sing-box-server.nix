{ ... }:
{
  flake.modules.nixos.sing-box-server =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.sing-box-server;
    in
    {
      meta.maintainers = [ "ocfox" ];

      options.services.sing-box-server = {
        enable = lib.mkEnableOption "sing-box server";
        secretName = lib.mkOption {
          type = lib.types.str;
          description = "Name of the kix secret containing the sing-box configuration JSON";
        };
      };

      config = lib.mkIf cfg.enable {
        kix.secrets.${cfg.secretName} = { };

        systemd.services.sing-box-server = {
          description = "sing-box server";
          after = [
            "network.target"
            "kix-activate.service"
          ];
          wants = [ "kix-activate.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStart = "${lib.getExe pkgs.sing-box} run -c ${config.kix.secrets.${cfg.secretName}.path}";
            Restart = "always";
            RestartSec = "3s";
            LimitNOFILE = 1048576;
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
