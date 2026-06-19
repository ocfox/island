{
  flake.modules.nixos.earlyoom = {
    services.earlyoom = {
      enable = true;
      freeMemThreshold = 5;
      freeSwapThreshold = 10;
    };
  };
}
