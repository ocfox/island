{
  flake.modules.nixos.fonts =
    { pkgs, ... }:
    {
      fonts = {
        enableDefaultPackages = false;
        fontDir.enable = true;
        fontconfig = {
          enable = true;
          antialias = true;

          defaultFonts = {
            emoji = [ "Noto Color Emoji" ];
            sansSerif = [
              "Noto Sans"
              "Noto Sans CJK JP"
            ];
            serif = [
              "Noto Serif CJK JP"
            ];
            monospace = [
              "JetBrainsMono Nerd Font"
              "Sarasa Mono J"
            ];
          };
        };

        packages = with pkgs; [
          noto-fonts
          sarasa-gothic
          noto-fonts-cjk-sans-static
          noto-fonts-cjk-serif
          noto-fonts-color-emoji
          nerd-fonts.jetbrains-mono
          dejavu_fonts
          freefont_ttf
          gyre-fonts
          liberation_ttf
          unifont
        ];
      };
    };
}
