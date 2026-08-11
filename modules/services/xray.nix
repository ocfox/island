{ ... }:
{
  flake.modules.nixos.xray =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.services.xray;
    in
    {
      meta.maintainers = [ "ocfox" ];

      options.services.xray = {
        secretName = lib.mkOption {
          type = lib.types.str;
          default = "light-xray";
          description = "Name of the kix secret containing the Xray configuration JSON";
        };
      };

      config = lib.mkIf cfg.enable {
        kix.secrets.${cfg.secretName} = { };
        services.xray.settingsFile = lib.mkDefault config.kix.secrets.${cfg.secretName}.path;
      };
    };
}
