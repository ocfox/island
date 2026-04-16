{
  flake.modules.nixos.android =
    { pkgs, config, ... }:
    {
      programs.adb.enable = true;
      users.users.${config.my.name}.extraGroups = [ "adbusers" ];
      environment.systemPackages = [
        pkgs.android-studio
      ];
      # nixpkgs.config.android_sdk.accept_license = true;
    };
}
