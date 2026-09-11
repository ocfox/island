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
        ++ (
          config.my.config
          |> lib.mapAttrsToList (
            key: source:
            let
              targetPath = "/home/${user}/.config/${key}";
              dir = dirOf targetPath;
            in
            [
              "d ${dir} - ${user} users - -"
              "L+ ${targetPath} - ${user} users - ${source}"
            ]
          )
          |> lib.concatLists
        );
    };
}
