{ inputs, ... }:
{
  flake.modules.nixos.disko =
    { pkgs, ... }:
    {
      imports = [
        inputs.disko.nixosModules.default
      ];

      nixpkgs.overlays = [
        (final: prev: {
          vmTools = prev.vmTools.override {
            kernelImage = "bzImage";
          };
        })
      ];
    };
}
