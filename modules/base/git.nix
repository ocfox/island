{
  flake.modules.nixos.git =
    { pkgs, ... }:
    {
      programs.git.enable = true;

      my.packages = [ pkgs.lazygit ];
    };
}
