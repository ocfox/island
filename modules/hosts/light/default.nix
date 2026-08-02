{ self, ... }:
{
  hosts.light = {
    system = "x86_64-linux";
    stateVersion = "26.11";
    # hostKey comes after the first deploy, from /var/lib/ssh/*.pub.
    module =
      { lib, ... }:
      {
        imports = with self.modules.nixos; [ vps ];

        fileSystems."/" = {
          device = "/dev/disk/by-uuid/f7aa78d3-e86c-4bd4-ac54-445d0a66b19a";
          fsType = "ext4";
        };

        fileSystems."/efi" = {
          device = "/dev/disk/by-uuid/0B6D-4B56";
          fsType = "vfat";
          options = [
            "fmask=0077"
            "dmask=0077"
          ];
        };
        swapDevices = [
          {
            device = "/swapfile";
            size = 2048;
          }
        ];
        zramSwap.enable = true;

        boot.loader.grub.enable = false;
        boot.loader.systemd-boot.enable = true;
        boot.loader.efi = {
          canTouchEfiVariables = true;
          efiSysMountPoint = "/efi";
        };

        # 20 GB of disk.
        documentation.enable = false;
        # man is not gated by documentation.enable.
        documentation.man.enable = false;
        services.pcscd.enable = lib.mkForce false;
        nix.extraOptions = lib.mkForce ''
          experimental-features = nix-command flakes ca-derivations
        '';
        nix.gc.options = lib.mkForce "--delete-older-than 7d";
        # Both pin the whole nixpkgs source into the closure.
        nix.registry = lib.mkForce { };
        nix.settings.nix-path = lib.mkForce [ ];
        system.tools.nixos-rebuild.enable = false;

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
