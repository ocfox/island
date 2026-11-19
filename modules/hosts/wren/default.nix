{ self, ... }:
{
  hosts.wren = {
    system = "x86_64-linux";
    stateVersion = "26.11";
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM34Ztt0vzdw0Cb33laRCAH1FSY8MvD/s3kKJNGFkyZQ root@wren";
    module =
      { ... }:
      {
        imports = with self.modules.nixos; [
          vps
          disko
          sing-box-server
        ];

        services.sing-box-server = {
          enable = true;
          secretName = "wren-sing-box";
        };

        boot.loader = {
          grub.enable = false;
          efi.canTouchEfiVariables = false;
          limine = {
            enable = true;
            efiSupport = true;
            efiInstallAsRemovable = true;
            biosSupport = true;
            biosDevice = "/dev/vda";
            partitionIndex = 1;
          };
        };

        systemd.network.networks."10-eth0" = {
          networkConfig = {
            DHCP = "no";
            IPv6AcceptRA = false;
          };
          address = [ "189.105.112.130/24" ];
          routes = [
            {
              Gateway = "189.105.112.254";
              GatewayOnLink = true;
            }
          ];
        };

        networking.nftables.tables.filter = {
          family = "inet";
          content = ''
            chain input {
              type filter hook input priority filter; policy drop;

              iif lo accept
              ct state { established, related } accept
              ct state invalid drop

              ip protocol icmp icmp type echo-request accept

              tcp dport 22 accept
              tcp dport 443 accept
            }

            chain forward {
              type filter hook forward priority filter; policy drop;
            }

            chain output {
              type filter hook output priority filter; policy accept;
            }
          '';
        };
      };
  };
}
