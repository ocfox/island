{ self, ... }:
{
  hosts.wall = {
    system = "x86_64-linux";
    stateVersion = "25.11";
    module =
      { pkgs, config, ... }:
      {
        imports = with self.modules.nixos; [
          boot
          disko
          facter
          desktop
        ];
        facter.reportPath = ./facter.json;
        services.blueman.enable = true;
        networking = {
          firewall.enable = false;
          nameservers = [ "10.10.0.157" ];
          proxy.default = "http://10.10.0.157:7890";
        };
        hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];
        boot.kernelParams = [
          "i915.force_probe=46d0"
          "i915.enable_guc=3"
        ];
        environment.systemPackages = [ pkgs.kodi-gbm ];
        users.users.${config.my.name}.extraGroups = [ "input" ];
      };
  };
}
