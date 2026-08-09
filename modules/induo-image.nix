{
  flake.modules.nixos.induo-image =
    {
      config,
      lib,
      pkgs,
      modulesPath,
      ...
    }:
    {
      system.build.diskImage = import (modulesPath + "/../lib/make-disk-image.nix") {
        inherit pkgs lib config;
        partitionTableType = "hybrid";
        format = "raw";
        diskSize = "auto";
        additionalSpace = "384M";
        installBootLoader = true;
        copyChannel = false;
        postVM = ''
          # limine bios-install failing does not fail the build, and the result
          # is an image that boots only under UEFI. Catch that here.
          if [ -z "$(${pkgs.coreutils}/bin/dd if="$out/nixos.img" bs=440 count=1 status=none | tr -d '\0')" ]; then
            echo "induo-image: MBR has no boot code, limine bios-install did not run" >&2
            exit 1
          fi
          ${pkgs.coreutils}/bin/stat -c %s "$out/nixos.img" > "$out/size"
          ${pkgs.zstd}/bin/zstd -T0 -9 --rm "$out/nixos.img"
        '';
      };

      # limine covers BIOS and UEFI from one image. biosSupport defaults to
      # !efiSupport, so both have to be set explicitly to get both.
      # Its BIOS stage needs a partition of the BIOS boot type, which in the
      # hybrid layout is partition 2 (1 is the ESP, 3 is the root).
      boot.loader.grub.enable = false;
      boot.loader.efi.canTouchEfiVariables = false;
      boot.loader.limine = {
        enable = true;
        efiSupport = true;
        efiInstallAsRemovable = true;
        biosSupport = true;
        biosDevice = "/dev/vda";
        partitionIndex = 2;
      };

      # By label, so it does not matter whether the target calls the disk
      # vda, sda or nvme0n1.
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

      # The image is built at minimum size and grown to fill the disk on first boot.
      boot.growPartition = true;

      # 512 MB targets OOM during boot without it.
      zramSwap.enable = lib.mkDefault true;
    };
}
