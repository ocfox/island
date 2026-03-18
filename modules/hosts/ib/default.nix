{ inputs, config, ... }:
let
  inherit (config.flake.lib) mkHostModule;
  nixosModules = config.flake.modules.nixos;
in
{
  flake.modules.nixos.ib =
    {
      pkgs,
      ...
    }:
    {
      imports = mkHostModule {
        stateVersion = "25.11";
        modules = with nixosModules; [
          inputs.jovian.nixosModules.default
          disko
          # podman

          desktop
          {
            jovian = {
              devices.steamdeck.enable = true;

              # steam = {
              #   enable = true;
              #   user = "ocfox";
              #   autoStart = true;
              #   desktopSession = "sway-uwsm";
              # };

              # decky-loader = {
              #   enable = true;
              #   user = "ocfox";
              # };
            };
          }

          { networking.networkmanager.enable = true; }
          {
            boot.loader = {
              timeout = 30;
              limine = {
                enable = true;
              };
              efi.canTouchEfiVariables = true;
            };

            # boot.kernelPackages = pkgs.linuxPackages_latest;

            zramSwap.enable = true;
            services.scx = {
              enable = true;
              scheduler = "scx_lavd";
            };

            environment.etc = {
              "machine-id".text = builtins.hashString "md5" ("ib") + "\n";
              "NIXOS".text = "";
            };
          }
        ];
      };
    };
}
