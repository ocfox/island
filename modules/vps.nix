{
  flake.modules.nixos.vps =
    {
      lib,
      modulesPath,
      ...
    }:
    {
      imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

      boot = {
        growPartition = lib.mkDefault true;
        initrd = {
          availableKernelModules = [
            "virtio_pci"
            "virtio_scsi"
            "virtio_blk"
            "virtio_net"
            "virtio_rng"
            "nvme"
            "nvme_core"
            "ena"
            "xen_blkfront"
            "xen_scsifront"
            "xen_netfront"
            "gve"
            "hv_storvsc"
            "hv_netvsc"
            "mana"
            "vmw_pvscsi"
            "vmxnet3"
            "ahci"
            "ata_piix"
            "ata_generic"
            "sd_mod"
            "sr_mod"
            "ehci_pci"
            "xhci_pci"
            "e1000e"
            "e1000"
            "igb"
            "ixgbevf"
            "mlx4_en"
            "mlx5_core"
          ];
          kernelModules = [ ];
        };
        kernelModules = [ ];
        extraModulePackages = [ ];
        kernelParams = [
          "console=tty0"
          "console=ttyAMA0,115200n8"
          "console=ttyS0,115200n8"
          "earlycon"
        ];
        supportedFilesystems = lib.mkDefault [
          "btrfs"
          "ext4"
          "vfat"
        ];
      };

      hardware.enableRedistributableFirmware = lib.mkForce false;
      i18n.extraLocales = lib.mkForce [ ];

      documentation = {
        enable = lib.mkForce false;
        man.enable = lib.mkForce false;
        nixos.enable = lib.mkForce false;
        info.enable = lib.mkForce false;
        doc.enable = lib.mkForce false;
      };

      fonts.fontconfig.enable = lib.mkForce false;

      programs = {
        command-not-found.enable = lib.mkDefault false;
        nano.enable = lib.mkDefault false;
        bash.completion.enable = lib.mkDefault false;
      };

      services = {
        pcscd.enable = lib.mkForce false;
        udisks2.enable = lib.mkDefault false;
      };
      security.polkit.enable = lib.mkDefault false;

      nix = {
        registry = lib.mkForce { };
        settings.nix-path = lib.mkForce [ ];
        channel.enable = false;
      };
      system.tools.nixos-rebuild.enable = lib.mkDefault false;

      zramSwap = {
        enable = lib.mkDefault true;
        algorithm = lib.mkDefault "zstd";
        memoryPercent = lib.mkDefault 50;
      };

      networking = {
        dhcpcd.enable = false;
        firewall.enable = false;
        useNetworkd = true;
        usePredictableInterfaceNames = false;
        nameservers = lib.mkDefault [
          "1.1.1.1"
          "8.8.8.8"
          "2606:4700:4700::1111"
          "2001:4860:4860::8888"
        ];
        nftables.enable = true;
      };

      systemd.network = {
        enable = true;
        networks."10-eth0" = {
          matchConfig.Name = "eth0";
          networkConfig.DHCP = lib.mkDefault "yes";
          linkConfig.RequiredForOnline = lib.mkDefault "routable";
        };
      };
    };
}
