{
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
              "Noto Sans"
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
          noto-fonts-cjk-serif
          noto-fonts-color-emoji
          nerd-fonts.jetbrains-mono
        ];
      };
    };
}
