{ self, ... }:
{
  hosts.mizu = {
    system = "x86_64-linux";
    stateVersion = "25.11";
    module =
      { pkgs, ... }:
      {
        imports = with self.modules.nixos; [ vps ];

        # Installed before induo existed: the MBR belongs to whatever set this
        # machine up, NixOS only rewrites grub.cfg. Reinstall with induo to get
        # a layout NixOS actually owns.
        boot.loader.grub = {
          enable = true;
          device = "nodev";
        };

        fileSystems."/" = {
          device = "/dev/disk/by-uuid/580fd907-a2af-478d-adf1-7a70edcca3be";
          fsType = "ext4";
        };
        swapDevices = [
          {
            device = "/swapfile";
            size = 1175;
          }
        ];
        environment.systemPackages = with pkgs; [
          hysteria
          tmux
        ];
        boot.kernel.sysctl."net.ipv6.conf.eth0.accept_ra" = false;
        boot.kernel.sysctl."net.ipv6.conf.eth0.autoconf" = false;
      };
  };
}
