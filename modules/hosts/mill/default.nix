{ self, ... }:
{
  hosts.mill = {
    system = "x86_64-linux";
    stateVersion = "26.11";
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBlnmVymMgcyhDifk3phrEHi6Fkn7WcadDrW5JwWBCZV root@mill";
    module =
      { config, ... }:
      {
        imports = with self.modules.nixos; [
          vps
          disko
        ];

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

        fileSystems."/data" = {
          device = "/dev/disk/by-uuid/047247c8-a897-42af-ba68-60d169ba8ce2";
          fsType = "ext4";
          options = [
            "defaults"
            "noatime"
          ];
        };

        fileSystems."/downloads" = {
          device = "/data/downloads";
          fsType = "none";
          options = [ "bind" ];
          depends = [ "/data" ];
        };

        networking.nftables.tables.filter = {
          family = "inet";
          content = ''
            chain input {
              type filter hook input priority filter; policy drop;

              iif lo accept
              iifname "tailscale0" accept
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
              tcp dport { 80, 443 } accept
              udp dport 443 accept
              tcp dport 37057 accept
              udp dport 37057 accept
            }

            chain forward {
              type filter hook forward priority filter; policy drop;
            }

            chain output {
              type filter hook output priority filter; policy accept;
            }
          '';
        };

        systemd.network.networks."10-eth0" = {
          networkConfig.DHCP = "no";
          address = [ "94.249.150.59/24" "2a12:bec4:1651:104::308/48" ];
          routes = [
            { Gateway = "94.249.150.1"; GatewayOnLink = true; }
            { Gateway = "2a12:bec4:1651::1"; GatewayOnLink = true; }
          ];
        };

        kix.secrets.cf-dns.mode = "640";
        security.acme = {
          acceptTerms = true;
          defaults.email = "civet@ocfox.me";
          certs."qbit.wren.asia" = {
            dnsProvider = "cloudflare";
            environmentFile = config.kix.secrets.cf-dns.path;
            group = "caddy";
          };
          certs."dufs.wren.asia" = {
            dnsProvider = "cloudflare";
            environmentFile = config.kix.secrets.cf-dns.path;
            group = "caddy";
          };
        };

        services.caddy = {
          enable = true;
          virtualHosts."qbit.wren.asia" = {
            useACMEHost = "qbit.wren.asia";
            extraConfig = ''
              reverse_proxy 127.0.0.1:8080
            '';
          };
          virtualHosts."dufs.wren.asia" = {
            useACMEHost = "dufs.wren.asia";
            extraConfig = ''
              reverse_proxy 127.0.0.1:5000
            '';
          };
        };
        users.users.caddy.extraGroups = [ "acme" ];

        users.users.media = {
          isSystemUser = true;
          group = "media";
        };
        users.groups.media = { };

        services.qbittorrent = {
          enable = true;
          user = "media";
          group = "media";
          profileDir = "/data/qbittorrent";
          webuiPort = 8080;
          torrentingPort = 37057;
        };
        systemd.services.qbittorrent.unitConfig.RequiresMountsFor = [
          "/data"
          "/downloads"
        ];

        kix.secrets.mill-dufs = { };
        services.dufs = {
          enable = true;
          user = "media";
          group = "media";
          servePath = "/data/downloads";
          bindAddresses = [ "127.0.0.1" ];
          port = 5000;
          environmentFile = config.kix.secrets.mill-dufs.path;
          settings = {
            allow-search = true;
            allow-archive = true;
          };
        };
        systemd.services.dufs.unitConfig.RequiresMountsFor = [ "/data" ];
      };
  };
}
