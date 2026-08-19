{ self, ... }:
{
  hosts.chest = {
    system = "x86_64-linux";
    stateVersion = "25.11";
    module =
      { ... }:
      {
        imports = with self.modules.nixos; [
          vps
        ];

        boot.growPartition = true;

        boot.loader.grub.enable = false;
        boot.loader.efi.canTouchEfiVariables = false;
        boot.loader.limine = {
          enable = true;
          efiSupport = true;
          efiInstallAsRemovable = true;
          biosSupport = true;
          biosDevice = "/dev/sda";
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
          networkConfig.DHCP = "ipv4";
          address = [ "2a01:4f8:1c1e:e1a8::1/64" ];
          routes = [
          { Gateway = "fe80::1"; }
          ];
        };
      };
  };
}
