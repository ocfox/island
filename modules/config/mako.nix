{
  flake.modules.nixos.mako =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      makoSettings = {
        "border-size" = 0;
        "ignore-timeout" = 1;
        "default-timeout" = 0;
        "border-color" = "#83b6af00";
        "background-color" = "#2b3339CC";
        font = "Sarasa Gothic J 12";
      };
    in
    {
      my.packages = [ pkgs.mako ];

      systemd.user.services.mako = {
        description = "Mako Notification Daemon";
        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.mako}/bin/mako";
          Restart = "on-failure";
          RestartSec = 1;
        };
      };

      my.config."mako/config" = pkgs.writeText "mako-config" (lib.generators.toKeyValue { } makoSettings);
    };
}
