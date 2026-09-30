{
  flake.modules.nixos.blender =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        pkgsRocm.blender
      ];
    };
}
