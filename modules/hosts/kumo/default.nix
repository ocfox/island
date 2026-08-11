{ self, ... }:
{
  hosts.kumo = {
    system = "x86_64-linux";
    stateVersion = "25.11";
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINGFOQAUa4fQiCbnD0lAoXI4HoYriPhCLAk/qOLS8IIC root@kumo";
    module =
      { config, ... }:
      {
        imports = with self.modules.nixos; [
          vps
          disko
          sandbox-runner
          memos
          vaultwarden
          mastodon
        ];

        # disko lays this disk out as EF02 (priority 1) + ESP + root, so the
        # BIOS stage has a partition of its own to live in. Confirm the index
        # with `sgdisk -p /dev/sda` before switching: a failing bios-install
        # does not fail activation, it just leaves the old boot code in place.
        boot.loader.limine = {
          enable = true;
          efiSupport = true;
          efiInstallAsRemovable = true;
          biosSupport = true;
          biosDevice = "/dev/sda";
          partitionIndex = 1;
        };
        boot.loader.efi.canTouchEfiVariables = false;

        networking.nftables.ruleset = ''
          table inet filter {
            chain input {
              type filter hook input priority filter; policy drop;

              iif lo accept
              ct state { established, related } accept
              ct state invalid drop

              ip6 nexthdr icmpv6 icmpv6 type {
                echo-request,
                nd-neighbor-solicit,
                nd-neighbor-advert,
                nd-router-advert,
                mld-listener-query,
              } accept

              tcp dport 22 accept
              tcp dport { 80, 443 } accept
              udp dport 443 accept

              # allow aqua agent (gallery) to push metrics to VictoriaMetrics
              ip saddr 100.64.0.1 tcp dport 9090 accept
            }

            chain forward {
              type filter hook forward priority filter; policy drop;
            }

            chain output {
              type filter hook output priority filter; policy accept;
            }
          }
        '';

        systemd.network.networks."10-eth0" = {
          address = [
            "2401:b60:e0fd:11::2/64"
            "2401:b60:e0fd:151::2/64"
            "2401:b60:e0fd:3d::2/64"
            "2401:b60:e0fd:2b::2/64"
          ];
          networkConfig = {
            DHCP = "no";
            IPv6AcceptRA = false;
          };
          routes = [ { Gateway = "2401:b60:e0fd:2b::1"; } ];
        };

        # The DC gives no IPv4 at all, so it comes from light over WireGuard:
        # the tunnel itself rides IPv6, and 0.0.0.0/0 inside it is the only
        # IPv4 route this host has.
        kix.secrets.kumo-wg = { };
        networking.wireguard.interfaces.wg0 = {
          ips = [ "10.99.0.2/24" ];
          privateKeyFile = config.kix.secrets.kumo-wg.path;
          peers = [
            {
              publicKey = "6eGDX3aUKFNQTikMlJPshzEeF0n9GkWHUKKvSJk9z1c=";
              allowedIPs = [ "0.0.0.0/0" ];
              endpoint = "[2406:da14:1200:e700:6a1a:86de:a0e8:f695]:51820";
              persistentKeepalive = 25;
            }
          ];
        };

        kix.secrets.cf-dns.mode = "640";
        security.acme = {
          acceptTerms = true;
          defaults.email = "civet@ocfox.me";
        };
        services.caddy.enable = true;
        users.users.caddy.extraGroups = [ "acme" ];

        kix.secrets.sandbox-api-key.mode = "640";
        services.sandbox-runner = {
          enable = true;
          domain = "exec.s4r.in";
          apiKeyFile = config.kix.secrets.sandbox-api-key.path;
        };

        services.vaultwarden.enable = true;
        services.memos.enable = true;
        services.mastodon = {
          enable = true;
          localDomain = "ocfox.me";
          configureNginx = false;
          streamingProcesses = 1;
          smtp = {
            host = "smtp.migadu.com";
            port = 587;
            user = "mastodon@ocfox.me";
            fromAddress = "mastodon@ocfox.me";
            passwordFile = config.kix.secrets.mastodon-smtp.path;
          };
          extraConfig.WEB_DOMAIN = "mastodon.ocfox.me";
          extraConfig.SINGLE_USER_MODE = "true";
        };
      };
  };
}
