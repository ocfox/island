{ self, ... }:
{
  hosts.cave = {
    system = "aarch64-linux";
    stateVersion = "25.11";
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOI13Y5GVOaICSu+q2oUFGqAW894ioVvEXY6q7KdYa6G root@cave";
    module =
      { ... }:
      {
        imports = with self.modules.nixos; [
          dnsproxy
          mihomo
        ];

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
        documentation.man.cache.enable = false;

        services.dnsproxy.enable = true;
        services.mihomo.enable = true;
      };
  };
}
