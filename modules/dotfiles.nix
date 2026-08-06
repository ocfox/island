{
  flake.modules.nixos.dotfiles =
    { lib, config, ... }:
    {
      options.my.config = lib.mkOption {
        type = with lib.types; attrsOf path;
        default = { };
        description = "Declarative dotfile management for the user, mapping directly to ~/.config/";
      };

      config.systemd.tmpfiles.rules =
        let
          user = config.my.name;
        in
        [
          "d /home/${user}/.config - ${user} users - -"
        ]
        ++ lib.flatten (
          lib.mapAttrsToList (
            key: source:
            let
              targetPath = "/home/${user}/.config/${key}";
              dir = "/home/${user}/.config/${lib.strings.removeSuffix (lib.last (lib.splitString "/" key)) key}";
            in
            [
              "d ${dir} - ${user} users - -"
              "L+ ${targetPath} - ${user} users - ${source}"
            ]
          ) config.my.config
        );
    };
}
