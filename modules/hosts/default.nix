{ config, ... }:
let
  inherit (config.flake.lib) mkNixosFromAttrs;
in
{
  flake.nixosConfigurations = mkNixosFromAttrs {
    everstone = "x86_64-linux";
    brick = "x86_64-linux";
    wall = "x86_64-linux";
    clare = "x86_64-linux";
    mizu = "x86_64-linux";
    cave = "aarch64-linux";
    laplace = "aarch64-linux";
  };
}
