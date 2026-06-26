{ self, inputs, ... }:
{
  hosts.gallery = {
    system = "x86_64-linux";
    stateVersion = "25.11";
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIXy3v9Nss7GHEzbsRBgmU+lUGPyl8mwZySBzYR1cVG+ root@everstone";
    module =
      { pkgs, config, ... }:
      {
        imports = with self.modules.nixos; [
          boot
          facter
          steam
          obs
          networkd
          desktop
          lact
        ];
        facter.reportPath = ./facter.json;
        kix.secrets.test = { };
        kix.secrets.aqua-token = {
          owner = config.my.name;
          group = "users";
          mode = "0400";
        };
        systemd.user.services.aqua-agent = {
          description = "Aqua desktop agent";
          wantedBy = [ "graphical-session.target" ];
          partOf = [ "graphical-session.target" ];
          serviceConfig = {
            ExecStart = "${pkgs.local.aqua.agent}/bin/aqua-agent";
            Environment = [
              "AQUA_TOKEN_FILE=${config.kix.secrets.aqua-token.path}"
              "AQUA_SERVER_HOST=aqua.s4r.in"
              "AQUA_SERVER_PORT=443"
              "AQUA_SERVER_TLS=true"
              "AQUA_CA_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "AQUA_IDLE_TIMEOUT_MS=30000"
            ];
            Restart = "on-failure";
            RestartSec = 2;
          };
        };
        hardware.i2c.enable = true;
        boot.initrd.kernelModules = [ "amdgpu" ];
        services.lact.enable = true;
        hardware.graphics.extraPackages = with pkgs; [
          rocmPackages.clr.icd
        ];
        environment.sessionVariables.LIBVA_DRIVER_NAME = "radeonsi";
        programs.nix-ld.enable = true;
        my.packages = with pkgs; [
          qbittorrent
          vesktop
          spotify
        ];
        services.blueman.enable = true;
        networking.firewall.enable = false;
        boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
        fileSystems."/" = {
          device = "/dev/disk/by-uuid/fe0ecfb9-db21-43f0-915a-70c37765f181";
          fsType = "btrfs";
        };
        fileSystems."/boot" = {
          device = "/dev/disk/by-uuid/3307-5F4E";
          fsType = "vfat";
        };
      };
  };
}
