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
        "nvme"
        "xen_blkfront"
        "vmw_pvscsi"
      ];
      boot.initrd.kernelModules = [ ];
      boot.kernelModules = [ ];
      boot.extraModulePackages = [ ];
      boot.kernelParams = [
        "console=ttyS0,115200n8"
        "console=tty0"
      ];

      # base is shaped for workstations: no VM loads firmware blobs, and
      # "all" builds every locale glibc has.
      hardware.enableRedistributableFirmware = lib.mkForce false;
      i18n.extraLocales = lib.mkForce [ ];

      networking = {
        dhcpcd.enable = false;
        firewall.enable = false;
        useNetworkd = true;
        usePredictableInterfaceNames = false;
        # Some providers only route DNS to their own resolvers.
        nameservers = lib.mkDefault [
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
          # Hosts with a static lease override DHCP and add address/routes here;
          # induo generates exactly that block.
          matchConfig.Name = "eth0";
          networkConfig.DHCP = lib.mkDefault "yes";
          linkConfig.RequiredForOnline = lib.mkDefault "routable";
        };
      };
    };
}
