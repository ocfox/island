{
  flake.modules.nixos.steam =
    { pkgs, ... }:
    {
      programs.steam = {
        enable = true;
      };
      programs.gamescope = {
        enable = true;
        capSysNice = false;
      };
      services.seatd.enable = true;
      environment.systemPackages = with pkgs; [
        gamescope-wsi
        mangohud
      ];
    };
}
