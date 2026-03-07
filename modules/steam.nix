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
      environment.systemPackages = with pkgs; [
        gamescope-wsi
      ];
    };
}
