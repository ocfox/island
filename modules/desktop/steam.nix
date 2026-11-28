{
  flake.modules.nixos.steam =
    { pkgs, config, ... }:
    {
      programs.steam = {
        enable = true;
        package = pkgs.steam.override {
          extraProfile = ''
            export XCURSOR_PATH="${pkgs.apple-cursor}/share/icons''${XCURSOR_PATH:+:$XCURSOR_PATH}"
            export XCURSOR_THEME="macOS"
            export XCURSOR_SIZE=24
          '';
        };
      };
      programs.gamescope = {
        enable = true;
        capSysNice = false;
      };
      hardware.xpadneo.enable = true;
      services.seatd.enable = true;
      environment.systemPackages = with pkgs; [
        gamescope-wsi
        mangohud
      ];
      systemd.tmpfiles.rules = [
        "r /home/${config.my.name}/.local/share/Steam/public/steam_tray_mono.png"
      ];
    };
}
