{ self, ... }:
{
  hosts.chest = {
    system = "x86_64-linux";
    stateVersion = "25.11";
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIChMEzSk0CPcDNCBYT1tlmGWGIW9qeTGKX6LL6+NJjep root@chest";
    module =
      { config, ... }:
      {
        imports = with self.modules.nixos; [
          vps
          sing-box-server
        ];

        users.users.parfait = {
          isNormalUser = true;
          extraGroups = [ "wheel" ];
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH19dnVW2sgzVKFIbeMRp3HfS564o5wzlp7YblJcEhbU ed25519 256-20260821"
          ];
        };

        security.sudo.wheelNeedsPassword = false;

        services.sing-box-server = {
          enable = true;
          secretName = "chest-sing-box";
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

        kix.secrets.chest-wg = { };
        networking.wireguard.interfaces.wg0 = {
          ips = [ "10.99.0.1/24" ];
          listenPort = 51820;
          privateKeyFile = config.kix.secrets.chest-wg.path;
          peers = [
            {
              publicKey = "4tfvxSxmkz69IABNAlWhyd80r/KabsdtotA7FTyXtxE=";
              allowedIPs = [ "10.99.0.2/32" ];
            }
          ];
        };

        # IPv4 exit for the IPv6-only kumo: WireGuard over IPv6, masqueraded
        # onto the Lightsail address.
        boot.kernel.sysctl = {
          "net.ipv4.conf.all.forwarding" = 1;
          "net.ipv6.conf.all.forwarding" = 1;
        };

        networking.nftables.tables = {
          filter = {
            family = "inet";
            content = ''
              chain input {
                type filter hook input priority filter; policy drop;

                iif lo accept
                iifname "wg0" accept
                ct state { established, related } accept
                ct state invalid drop

                ip6 nexthdr icmpv6 icmpv6 type {
                  echo-request,
                  nd-neighbor-solicit,
                  nd-neighbor-advert,
                  nd-router-advert,
                  mld-listener-query,
                } accept
                ip protocol icmp icmp type echo-request accept

                tcp dport 22 accept
                tcp dport 443 accept
                tcp dport 8388 accept
                udp dport 8388 accept
                udp dport 51820 accept
              }

              chain forward {
                type filter hook forward priority filter; policy drop;

                iifname "wg0" oifname "eth0" accept
                iifname "eth0" oifname "wg0" ct state { established, related } accept
              }

              chain output {
                type filter hook output priority filter; policy accept;
              }
            '';
          };

          nat = {
            family = "ip";
            content = ''
              chain postrouting {
                type nat hook postrouting priority srcnat; policy accept;

                iifname "wg0" oifname "eth0" masquerade
              }
            '';
          };
        };
      };
  };
}
