{ inputs, ... }:
{
  flake.modules.nixos.vertere =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.services.vertere;
    in
    {
      meta.maintainers = [ "ocfox" ];
      imports = [ inputs.vertere.nixosModules.default ];

      config = lib.mkIf cfg.enable {
        kix.secrets.vertere = {
          mode = "400";
          owner = config.my.name;
        };
        services.vertere.environmentFile = lib.mkDefault config.kix.secrets.vertere.path;
      };
    };
}
