{ self, ... }:
{
  hosts.mini = {
    system = "x86_64-linux";
    stateVersion = "26.11";
    useBase = false;
    module =
      { ... }:
      {
        imports = with self.modules.nixos; [
          minimal
          vps
          disko
        ];

        users = {
          mutableUsers = false;
          users.root = {
            initialHashedPassword = "$6$4HQysWQ6mvyu/mnd$RqL.hhK.t11RrgiIdzHEerR/Nqwk9TVo7nMdPAT0tBnQW39NnwR8mnvIRKtqSQupjdh/zVwzf5KT19.xn4Elf.";
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICFP2wSho7RDutjcMwnvPHHMnQcvuqX841gHlQdkpTdc me@s4r.in"
            ];
          };
        };

        systemd.network.networks."10-eth0" = {
          networkConfig.DHCP = "ipv4";
          address = [ "2a01:4f8:1c18:41d0::1/64" ];
          routes = [
          { Gateway = "fe80::1"; GatewayOnLink = true; }
          ];
        };
      };
  };
}
