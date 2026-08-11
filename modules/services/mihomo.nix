{ ... }:
{
  flake.modules.nixos.mihomo =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.mihomo;
    in
    {
      meta.maintainers = [ "ocfox" ];

      config = lib.mkIf cfg.enable {
        kix.secrets.mihomo.mode = "640";

        services.mihomo = {
          tunMode = lib.mkDefault true;
          webui = lib.mkDefault pkgs.metacubexd;
          configFile = lib.mkDefault config.kix.secrets.mihomo.path;
        };
      };
    };
}
