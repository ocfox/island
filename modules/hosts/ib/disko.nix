{
  flake.modules.nixos.ib.disko.devices = {
    disko.devices = {
      disk.one = {
        device = "/dev/nvme0n1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "bcachefs";
                filesystem = "main";
              };
            };
          };
        };
      };

      bcachefs_filesystems.main = {
        type = "bcachefs_filesystem";
        extraFormatArgs = [
          "--compression=zstd"
          "--background_compression=zstd"
          "--discard"
          "--noatime"
        ];
        subvolumes = {
          "root" = {
            mountpoint = "/";
          };
          "nix" = {
            mountpoint = "/nix";
          };
          "home" = {
            mountpoint = "/home";
          };
        };
      };
    };
  };
}
