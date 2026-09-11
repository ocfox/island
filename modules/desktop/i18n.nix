{
  flake.modules.nixos.i18n = {
    time.timeZone = "Asia/Shanghai";
    i18n = {
      defaultLocale = "en_US.UTF-8";
      extraLocales = "all";
      extraLocaleSettings = {
        LC_TIME = "ja_JP.UTF-8";
      };
    };
  };

  flake.modules.nixos.fcitx =
    { pkgs, ... }:
    {
      i18n.inputMethod = {
        enable = true;
        type = "fcitx5";
        fcitx5.waylandFrontend = true;
        fcitx5.addons = with pkgs; [
          qt6Packages.fcitx5-chinese-addons
          fcitx5-mozc
          qt6Packages.fcitx5-configtool
        ];
      };

      environment.variables.GTK_IM_MODULE = "fcitx";
    };
}
