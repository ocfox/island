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
        fcitx5.addons = with pkgs; [
          qt6Packages.fcitx5-chinese-addons
          fcitx5-mozc
          qt6Packages.fcitx5-configtool
        ];
      };
    };

  flake.modules.nixos.fonts =
    { pkgs, ... }:
    {
      fonts = {
        fontDir.enable = true;
        fontconfig = {
          enable = true;
          antialias = true;

          defaultFonts = {
            emoji = [ "Noto Color Emoji" ];
            sansSerif = [
              "Inter"
              "Sarasa Gothic J"
            ];
            serif = [
              "Sarasa Gothic J"
            ];
            monospace = [
              "JetBrainsMono Nerd Font"
              "Sarasa Mono J"
            ];
          };
        };

        packages = with pkgs; [
          inter
          sarasa-gothic
          local.lxgw-zhisong
          local.lxgw-neoxihei
          noto-fonts-color-emoji
          nerd-fonts.jetbrains-mono
        ];
      };
    };
}
