{
  flake.modules.nixos.networkd = {
    networking.dhcpcd.enable = false;
    networking.useNetworkd = true;
    networking.wireless.iwd.enable = true;

    systemd.network = {
      enable = true;
      networks."20-wired" = {
        matchConfig.Name = "en*";
        networkConfig.DHCP = "yes";
      };
    };
  };
}
