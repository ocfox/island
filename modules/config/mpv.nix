{
  flake.modules.nixos.mpv =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    {
      my.packages = [
        (pkgs.mpv.override { scripts = [ pkgs.mpvScripts.uosc ]; })
      ];

      my.config = {
        mpv = {
          "mpv.conf" = pkgs.writeText "mpv.conf" (
            lib.generators.toKeyValue { } {
              vo = "gpu-next";
              gpu-api = "vulkan";
              hwdec = "vaapi";
              gpu-context = "waylandvk";
              cache = "yes";
              target-colorspace-hint = "yes";
            }
          );
        };
      };
    };
}
