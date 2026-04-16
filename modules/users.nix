{
  flake.modules.nixos.users =
    { lib, config, ... }:
    {
      options = {
        my.name = lib.mkOption {
          type = lib.types.str;
          default = "ib";
          description = "The primary user for this configuration.";
        };

        my.config = lib.mkOption {
          type = with lib.types; attrsOf path;
          default = { };
          description = "Declarative dotfile management for the user, mapping directly to ~/.config/";
        };

        my.packages = lib.mkOption {
          type = with lib.types; listOf package;
          default = [ ];
          description = "A list of packages to be installed for the primary user.";
        };
      };

      config = lib.mkMerge [
        {
          systemd.tmpfiles.rules = lib.flatten (
            lib.mapAttrsToList (
              key: source:
              let
                user = config.my.name;
                targetPath = "/home/${user}/.config/${key}";
                dir = "/home/${user}/.config/${lib.strings.removeSuffix (lib.last (lib.splitString "/" key)) key}";
              in
              [
                "d ${dir} - ${user} users - -"
                "L+ ${targetPath} - ${user} users - ${source}"
              ]
            ) config.my.config
          );
        }
        {
          my.name = "ib";

          users.users.${config.my.name} = {
            isNormalUser = true;
            group = "users";
            uid = 1000;
            hashedPassword = "$6$jVI2tdENaEqUyZGh$rni.joO5US9t9RYM9wlIvia4L1YOObs44Kt3gBcooBJTeSFGyEorciM2CrKMEnzbojpi1KgPPe256i5Q46N1d0";
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHysCjoqwXAumW+cUCcFZDpC9yLx3Jh7x5du7r21fPE4"
              "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIHnLWTS5/vPyPFY+tCVYn3Ejf3NQpQzcGnWLQTyE7lbzAAAAC3NzaDpwYXNzZm94 ssh:passfox"
            ];
            extraGroups = [
              "adbusers"
              "wheel"
              "podman"
              "seat"
              "realtime"
              "dialout"
              "libvirtd"
            ];
            packages = config.my.packages;
          };

          users = {
            mutableUsers = false;
            users = {
              root.isSystemUser = true;
              root.hashedPassword = "$6$jVI2tdENaEqUyZGh$rni.joO5US9t9RYM9wlIvia4L1YOObs44Kt3gBcooBJTeSFGyEorciM2CrKMEnzbojpi1KgPPe256i5Q46N1d0";
            };
          };

          services.userborn.enable = true;
        }
      ];
    };
}
