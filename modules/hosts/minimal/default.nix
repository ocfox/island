{ self, ... }:
{
  hosts.minimal = {
    system = "x86_64-linux";
    stateVersion = "26.05";
    module =
      { ... }:
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
      };
  };
}
