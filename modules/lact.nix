{
  flake.modules.nixos.lact =
    { ... }:
    {
      nixpkgs.overlays = [
        (_final: prev: {
          lact = prev.lact.overrideAttrs (old: {
            postPatch =
              old.postPatch
              + ''
                substituteInPlace lact-daemon/src/config.rs \
                  --replace-fail '"/etc/lact"' '"/var/lib/lact"'
                substituteInPlace lact-daemon/src/server/handler.rs \
                  --replace-fail '"/etc/lact/config.yaml"' '"/var/lib/lact/config.yaml"' \
                  --replace-fail '"/run/host/root/etc/lact/config.yaml"' '"/run/host/root/var/lib/lact/config.yaml"'
              '';
          });
        })
      ];

      systemd.services.lactd.serviceConfig.StateDirectory = "lact";
    };
}
