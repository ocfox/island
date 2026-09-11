{
  flake.modules.nixos.boot =
    { config, pkgs, ... }:
    {
      boot.loader = {
        timeout = 30;
        limine.enable = true;
        limine.maxGenerations = 10;
        limine.extraEntries = ''
          /Windows
              comment: Windows Boot Manager (nvme0n1p4)
              protocol: efi_chainload
              path: boot():/EFI/Microsoft/Boot/bootmgfw.efi
        '';
        efi.canTouchEfiVariables = true;
      };

      system.nixos-init.enable = true;
      system.etc.overlay.enable = true;
      system.etc.overlay.mutable = false;
      boot.initrd.systemd.enable = true;

      boot.kernelPackages = pkgs.linuxPackages_latest;

      zramSwap.enable = true;
      services.scx = {
        enable = true;
        scheduler = "scx_lavd";
      };

      environment.etc = {
        "machine-id".text = builtins.hashString "md5" (config.networking.hostName) + "\n";
        "NIXOS".text = "";
      };
    };
}
