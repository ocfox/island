{ self, inputs, ... }:
{
  hosts.laplace = {
    system = "aarch64-linux";
    stateVersion = "25.11";
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID8IVBgnE6cfei0k4va0fyzyoh9o62f9yM3FwGhnPJON";
    module =
      { config, ... }:
      {
        imports = with self.modules.nixos; [ facter disko ];
        facter.reportPath = ./facter.json;
        kix.secrets.drive = {
          file = inputs.self + "/secrets/drive.age";
          mode = "640";
        };
        fileSystems."/var/lib/immich/library" = {
          device = "immich:immich";
          fsType = "rclone";
          options = [
            "nodev"
            "nofail"
            "allow_other"
            "args2env"
            "vfs-cache-mode=writes"
            "config=${config.kix.secrets.drive.path}"
          ];
        };
        security.acme = {
          acceptTerms = true;
          defaults.email = "civet@ocfox.me";
        };
        boot.loader.grub = {
          efiSupport = true;
          efiInstallAsRemovable = true;
        };
        boot.initrd = {
          compressor = "zstd";
          compressorArgs = [ "-19" "-T0" ];
          systemd.enable = true;
        };
        services = {
          immich.enable = true;
          caddy = {
            enable = true;
            email = "chi@ocfox.me";
            virtualHosts."immich" = {
              hostName = "immich.ocfox.me";
              extraConfig = "reverse_proxy localhost:2283";
            };
          };
        };
        networking.firewall.enable = false;
        networking.useDHCP = false;
        systemd.network = {
          enable = true;
          networks."eth0" = {
            matchConfig.MACAddress = "96:00:04:4e:89:6d";
            address = [ "94.130.74.166/32" "2a01:4f8:1c1c:dd43::1/64" ];
            routes = [
              { Gateway = "fe80::1"; }
              { Gateway = "172.31.1.1"; GatewayOnLink = true; }
            ];
            linkConfig.RequiredForOnline = "routable";
          };
        };
      };
  };
}
