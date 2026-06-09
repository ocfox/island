{
  flake.modules.nixos.vps =
    { lib, modulesPath, ... }:
    {
      imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

      boot.initrd.availableKernelModules = [
        "ata_piix"
        "uhci_hcd"
        "virtio_pci"
        "virtio_scsi"
        "ehci_pci"
        "xhci_pci"
        "sr_mod"
        "virtio_blk"
        "ahci"
        "xen_blkfront"
        "vmw_pvscsi"
      ];
      boot.initrd.kernelModules = [ ];
      boot.kernelModules = [ "kvm-amd" ];
      boot.extraModulePackages = [ ];
      boot.loader.grub = {
        enable = true;
        device = lib.mkDefault "nodev";
      };
      boot.kernelParams = [
        "console=ttyS0,115200n8"
        "console=tty0"
      ];

      networking = {
        dhcpcd.enable = false;
        firewall.enable = false;
        useNetworkd = true;
        usePredictableInterfaceNames = false;
        nameservers = [
          "1.1.1.1"
          "8.8.8.8"
          "2606:4700:4700::1111"
          "2001:4860:4860::8888"
        ];
        nftables = {
          enable = true;
        };
      };

      systemd.network = {
        enable = true;
        networks."10-eth0" = {
          matchConfig.Name = "eth0";
          networkConfig.DHCP = lib.mkDefault "yes";
          linkConfig.RequiredForOnline = "routable";
        };
      };
    };
}
