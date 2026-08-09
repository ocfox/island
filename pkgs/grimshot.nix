{ sway-contrib, local }:

# grimshot wraps itself with a fixed PATH, so it has to be rebuilt to pick up
# the patched grim rather than the one from nixpkgs-wayland
sway-contrib.grimshot.override { inherit (local) grim; }
