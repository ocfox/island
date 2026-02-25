{
  flake.modules.nixos.git =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      settingsFormat = pkgs.formats.ini { };

      gitSettings = {
        # gpg = {
        #   format = "ssh";
        # };
        user = {
          name = "ocfox";
          email = "i@ocfox.me";
          # signingKey = "key::sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIHnLWTS5/vPyPFY+tCVYn3Ejf3NQpQzcGnWLQTyE7lbzAAAAC3NzaDpwYXNzZm94 ssh:passfox";
        };
        # commit = {
        #   gpgSign = true;
        # };
      };
    in
    {
      my.packages = [
        pkgs.git
        pkgs.lazygit
      ];

      my.config.git = {
        "config" = settingsFormat.generate "git-config" gitSettings;
      };
    };
}
