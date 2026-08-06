{
  flake.modules.nixos.git =
    { pkgs, ... }:
    {
      my.packages = [
        pkgs.git
        pkgs.lazygit
      ];
    };
}
