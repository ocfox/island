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
            # Storage controllers & block devices
            "virtio_pci"
            "virtio_scsi"
            "virtio_blk"
            "nvme"
            "nvme_core"
            "ahci"
            "ata_piix"
            "ata_generic"
            "sd_mod"
            "sr_mod"
            "sg"
            "xen_blkfront"
            "xen_scsifront"
            "hv_storvsc"
            "hv_vmbus"
            "hv_balloon"
            "hv_utils"
            "vmw_pvscsi"
            "mptspi"
            "uas"
            "dm_mod"
            "fuse"

            # Cloud & physical network interfaces
            "virtio_net"
            "net_failover"
            "failover"
            "ena"
            "gve"
            "hv_netvsc"
            "mana"
            "xen_netfront"
            "vmxnet3"
            "e1000e"
            "e1000"
            "igb"
            "ixgbevf"
            "r8169"
            "tg3"
            "bnxt_en"
            "mlx4_en"
            "mlx5_core"

            # Core network protocols, sockets & netfilter
            "af_packet"
            "af_packet_diag"
            "inet_diag"
            "unix_diag"
            "raw_diag"
            "tcp_diag"
            "udp_diag"
            "ip_tunnel"
            "ip6_tunnel"
            "tunnel4"
            "tunnel6"
            "sit"
            "nf_tables"
            "nft_compat"
            "nft_chain_nat"
            "nf_nat"
            "nf_conntrack"
            "nf_conntrack_netlink"
            "nft_fib"
            "nft_fib_inet"
            "nft_fib_ipv4"
            "nft_fib_ipv6"
            "nft_masq"
            "nft_ct"
            "nft_reject"
            "nft_reject_inet"
            "nft_reject_ipv4"
            "nft_reject_ipv6"
            "x_tables"
            "xt_tcpudp"
            "xt_conntrack"
            "xt_addrtype"
            "xt_comment"
            "xt_multiport"
            "xt_nat"
            "xt_MASQUERADE"

            # Input, console & display
            "atkbd"
            "i8042"
            "serio"
            "serio_raw"
            "usbhid"
            "hid"
            "hid_generic"
            "virtio_input"
            "virtio_console"
            "virtio_gpu"
            "hyperv_keyboard"

            # Virtualization bus, hypervisor services & watchdog
            "virtio"
            "virtio_ring"
            "virtio_pci_modern_dev"
            "virtio_pci_legacy_dev"
            "virtio_balloon"
            "virtio_dma_buf"
            "virtio_mmio"
            "virtio_rng"
            "vsock"
            "vmw_vsock_virtio_transport_common"
            "vsock_loopback"
            "i2c_i801"
            "lpc_ich"
            "iTCO_wdt"
            "9p"
            "9pnet"
            "9pnet_virtio"
            "virtiofs"

            # Filesystems & compression
            "btrfs"
            "ext4"
            "vfat"
            "fat"
            "xfs"
            "zstd"
            "zstd_compress"
            "crc32c"
            "nls_cp437"
            "nls_iso8859_1"
            "overlay"
            "zram"
          ];
          kernelModules = [ ];
        };
        kernelModules = [ ];
        extraModulePackages = [ ];
        kernelParams = [
          "console=tty1"
          "console=ttyS0,115200"
          "console=ttyAMA0,115200"
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
