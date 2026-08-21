{ self, ... }:
{
  hosts.light = {
    system = "x86_64-linux";
    stateVersion = "26.11";
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXqpaUrrGe+JsXLzdgxkX10J8jzVXLss0JfpQVO/bOX root@nixos";
    module =
      { config, ... }:
      {
        imports = with self.modules.nixos; [
          vps
          disko
          xray
        ];

        boot.loader = {
          grub.enable = false;
          efi.canTouchEfiVariables = false;
          limine = {
            enable = true;
            efiSupport = true;
            efiInstallAsRemovable = true;
            biosSupport = true;
            biosDevice = "/dev/nvme0n1";
            partitionIndex = 1;
          };
        };

        systemd.network.networks."10-eth0".address = [
          "2406:da14:1200:e700:6a1a:86de:a0e8:f695/128"
        ];

        services.xray = {
          enable = true;
          secretName = "light-xray";
        };

        kix.secrets.light-wg = { };
        networking.wireguard.interfaces.wg0 = {
          ips = [ "10.99.0.1/24" ];
          listenPort = 51820;
          privateKeyFile = config.kix.secrets.light-wg.path;
          peers = [
            {
              publicKey = "4tfvxSxmkz69IABNAlWhyd80r/KabsdtotA7FTyXtxE=";
              allowedIPs = [ "10.99.0.2/32" ];
            }
          ];
        };

        # IPv4 exit for the IPv6-only kumo: WireGuard over IPv6, masqueraded
        # onto the Lightsail address. A single /128 leaves no prefix for a
        # NAT64 range, and given a tunnel anyway NAT44 is the simpler half --
        # kumo gets a real IPv4 stack, so no DNS64 and no CLAT.
        boot.kernel.sysctl = {
          "net.ipv4.conf.all.forwarding" = 1;
          "net.ipv6.conf.all.forwarding" = 1;
        };

        networking.nftables.ruleset = ''
          table inet filter {
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
          }

          table ip nat {
            chain postrouting {
              type nat hook postrouting priority srcnat; policy accept;

              iifname "wg0" oifname "eth0" masquerade
            }
          }
        '';
      };
  };
}
