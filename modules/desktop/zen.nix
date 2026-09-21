{ inputs, ... }:
{
  flake.modules.nixos.zen =
    { pkgs, ... }:
    {
      my.packages = [
        (pkgs.wrapFirefox
          (inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.zen-browser-unwrapped.overrideAttrs (old: {
            passthru = (old.passthru or { }) // {
              withFFmpeg = true;
              withGSSAPI = true;
            };
          }))
          {
            pname = "zen-browser";
          })
      ];
    };
}
