{ self, ... }:
{
  hosts.chest = {
    system = "x86_64-linux";
    stateVersion = "25.11";
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIChMEzSk0CPcDNCBYT1tlmGWGIW9qeTGKX6LL6+NJjep root@chest";
    module =
      { ... }:
      {
        imports = with self.modules.nixos; [
          vps
          xray
        ];

        services.xray = {
          enable = true;
          secretName = "chest-xray";
        };

        boot.growPartition = true;

        boot.loader.grub.enable = false;
        boot.loader.efi.canTouchEfiVariables = false;
        boot.loader.limine = {
          enable = true;
          efiSupport = true;
          efiInstallAsRemovable = true;
          biosSupport = true;
          biosDevice = "/dev/nvme0n1";
          partitionIndex = 2;
        };

        fileSystems."/" = {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
          autoResize = true;
        };

        fileSystems."/boot" = {
          device = "/dev/disk/by-label/ESP";
          fsType = "vfat";
          options = [
            "fmask=0077"
            "dmask=0077"
          ];
        };
        systemd.network.networks."10-eth0" = {
          address = [ "2406:da14:1344:7e00:3e2a:e541:5303:12e1/128" ];
        };
      };
  };
}
