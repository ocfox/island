{ inputs, ... }:
{
  flake.modules.nixos.zen =
    { pkgs, ... }:
    {
      my.packages = [
        inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];
    };
}
