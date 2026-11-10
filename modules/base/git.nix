{
  flake.modules.nixos.git =
    { pkgs, ... }:
    {
      programs.git = {
        enable = true;
        config = {
          credential.helper = "store";
        };
      };

      my.packages = [ pkgs.lazygit ];
    };
}
