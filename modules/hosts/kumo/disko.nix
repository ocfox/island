{
  flake.modules.nixos.kumo.disko.devices = {
    disk.disk1 = {
      type = "disk";
      device = "/dev/sda";
      content = {
        type = "gpt";
        partitions = {
          MBR = {
            type = "EF02";
            size = "1M";
            priority = 1;
          };
          ESP = {
            type = "EF00";
            size = "500M";
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
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "/rootfs" = {
                  mountpoint = "/";
                };
                "/home" = {
                  mountOptions = [ "compress=zstd" ];
                  mountpoint = "/home";
                };
                "/nix" = {
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                  mountpoint = "/nix";
                };
                "/swap" = {
                  mountpoint = "/.swapvol";
                  swap = {
                    swapfile.size = "2G";
                  };
                };
              };

              mountpoint = "/partition-root";
              swap = {
                swapfile = {
                  size = "2G";
                };
              };
            };
          };
        };
      };
    };
  };
}
