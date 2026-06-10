{ inputs, config, ... }:
let
  inherit (config.flake.lib) mkHostModule;
in
{
  flake.modules.nixos.cave =
    { config, pkgs, ... }:
    {
      imports = mkHostModule {
        stateVersion = "25.11";
        hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOI13Y5GVOaICSu+q2oUFGqAW894ioVvEXY6q7KdYa6G root@cave";
        modules = [
          {
            kix.secrets.mihomo = {
              file = inputs.self + "/secrets/mihomo.age";
              mode = "640";
            };
            boot.loader.generic-extlinux-compatible.enable = true;
            boot.loader.grub.enable = false;

            fileSystems."/" = {
              device = "/dev/disk/by-uuid/44444444-4444-4444-8888-888888888888";
              fsType = "ext4";
            };

            fileSystems."/var/log" = {
              device = "tmpfs";
              fsType = "tmpfs";
            };

            networking.useDHCP = true;
            networking.firewall.enable = false;

            boot.kernel.sysctl = {
              "net.ipv6.conf.all.forwarding" = 1;
              "net.ipv4.conf.all.forwarding" = 1;
            };

            documentation.man.generateCaches = false;

            services = {
              resolved.enable = false;
              dnsproxy = {
                enable = true;
                flags = [
                  "--cache"
                  "--cache-optimistic"
                  "--edns"
                ];
                settings = {
                  bootstrap = [
                    "8.8.8.8"
                    "119.29.29.29"
                    "tcp://223.6.6.6:53"
                  ];
                  listen-addrs = [ "0.0.0.0" ];
                  listen-ports = [ 53 ];
                  upstream-mode = "parallel";
                  upstream = [
                    "https://1.1.1.1/dns-query"
                    "h3://dns.alidns.com/dns-query"
                    "tls://dot.pub"
                  ];
                };
              };
              mihomo = {
                enable = true;
                tunMode = true;
                webui = pkgs.metacubexd;
                configFile = config.kix.secrets.mihomo.path;
              };
            };
          }
        ];
      };
    };
}
