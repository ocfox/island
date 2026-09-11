{
  flake.modules.nixos.dotfiles =
    { lib, config, ... }:
    {
      options.my.config = lib.mkOption {
        type = with lib.types; attrsOf path;
        default = { };
        description = "Declarative dotfile management for the user, mapping directly to ~/.config/";
      };

      config.systemd.tmpfiles.settings."10-dotfiles" =
        let
          user = config.my.name;
          baseDir = {
            "/home/${user}/.config".d = {
              inherit user;
              group = "users";
            };
          };
          rules =
            config.my.config
            |> lib.mapAttrsToList (
              key: source:
              let
                targetPath = "/home/${user}/.config/${key}";
                dir = dirOf targetPath;
              in
              {
                ${dir}.d = {
                  inherit user;
                  group = "users";
                };
                ${targetPath}."L+" = {
                  argument = "${source}";
                  inherit user;
                  group = "users";
                };
              }
            );
        in
        lib.mkMerge ([ baseDir ] ++ rules);
    };
}
