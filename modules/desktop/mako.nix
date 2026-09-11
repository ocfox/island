{
  flake.modules.nixos.mako =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      makoConfig = ''
        max-visible=5
        sort=-time
        layer=overlay
        anchor=top-right
        width=360
        height=130
        margin=16
        padding=12,16
        border-size=2
        border-radius=4
        font=Sarasa Gothic J 11
        icons=1
        max-icon-size=48
        background-color=#2b3339F5
        text-color=#d3c6aa
        border-color=#83b6af
        progress-color=over #a7c080
        default-timeout=5000
        ignore-timeout=0
        on-button-left=dismiss
        on-button-right=dismiss-all
        on-button-middle=invoke-default-action

        [urgency=low]
        background-color=#2b3339F5
        border-color=#7a8478
        text-color=#9da9a0
        default-timeout=3000

        [urgency=normal]
        background-color=#2b3339F5
        border-color=#83b6af
        text-color=#d3c6aa
        default-timeout=5000

        [urgency=critical]
        background-color=#2b3339F5
        border-color=#e68183
        text-color=#e68183
        default-timeout=0

        [app-name=grimshot]
        default-timeout=2500
      '';
    in
    {
      my.packages = [ pkgs.mako ];

      systemd.user.services.mako = {
        description = "Mako Notification Daemon";
        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        requisite = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.mako}/bin/mako";
          Restart = "on-failure";
          RestartSec = 1;
        };
      };

      my.config."mako/config" = pkgs.writeText "mako-config" makoConfig;
    };
}
