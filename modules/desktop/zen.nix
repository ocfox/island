{
  flake.modules.nixos.zen =
    { pkgs, ... }:
    {
      my.packages = [
        pkgs.local.zen-browser
      ];
    };
}
