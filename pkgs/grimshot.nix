{ sway-contrib, local }:

# grimshot wraps itself with a fixed PATH, so it has to be rebuilt to pick up
# milk (our 4K HDR screenshot engine) rather than grim
sway-contrib.grimshot.override { grim = local.milk; }
