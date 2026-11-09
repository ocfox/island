{
  flake.modules.nixos.steam =
    { pkgs, config, ... }:
    {
      programs.steam = {
        enable = true;
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
