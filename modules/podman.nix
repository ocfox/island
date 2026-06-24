{
  flake.modules.nixos.podman =
    { pkgs, config, ... }:
    {
      virtualisation = {
        containers.enable = true;
        podman = {
          enable = true;
          dockerCompat = true;
          defaultNetwork.settings.dns_enabled = true;
        };
      };

      # Rootless: activate user socket on login via socket activation
      systemd.user.sockets.podman = {
        wantedBy = [ "sockets.target" ];
      };

      # docker / docker-compose pick up the rootless podman socket
      environment.sessionVariables.DOCKER_HOST =
        "unix:///run/user/${toString config.users.users.${config.my.name}.uid}/podman/podman.sock";

      # docker compose v2 standalone (podman doesn't support Docker CLI plugins)
      environment.systemPackages = [ pkgs.docker-compose ];
    };
}
