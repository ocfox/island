{ self, inputs, ... }:
{
  hosts.gallery = {
    system = "x86_64-linux";
    stateVersion = "25.11";
    module =
      { pkgs, config, ... }:
      {
        imports =
          with self.modules.nixos;
          [
            boot
            facter
            steam
            networkd
            desktop
          ]
          ++ [ inputs.kix.nixosModules.default ];
        facter.reportPath = ./facter.json;
        kix.settings.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIXy3v9Nss7GHEzbsRBgmU+lUGPyl8mwZySBzYR1cVG+ root@everstone";
        kix.secrets = {
          sarin-cf.file = inputs.self + "/secrets/sarin.cf.age";
          sarin-cf-cr.file = inputs.self + "/secrets/sarin.cf.cr.age";
        };
        hardware.i2c.enable = true;
        hardware.graphics.extraPackages = with pkgs; [
          intel-media-driver
          vpl-gpu-rt
          level-zero
          intel-compute-runtime
        ];
        boot.kernelParams = [
          "i915.force_probe=56a1"
          "i915.enable_guc=3"
        ];
        environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
        programs.nix-ld.enable = true;
        my.packages = with pkgs; [ qbittorrent vesktop spotify ];
        services.blueman.enable = true;
        services.cloudflared = {
          enable = true;
          certificateFile = config.kix.secrets.sarin-cf.path;
          tunnels.test = {
            credentialsFile = config.kix.secrets.sarin-cf-cr.path;
            default = "http_status:404";
            ingress."testcf.s4r.in".service = "http://localhost:3000";
          };
        };
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
