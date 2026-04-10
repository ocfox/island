{
  flake.modules.nixos.ctct =
    { pkgs, ... }:
    {
      systemd.user.services.ctct = {
        description = "ctct";
        wantedBy = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.local.ctct}/bin/ctct";
          Restart = "on-failure";
          RestartSec = 1;
        };
      };
    };
}
