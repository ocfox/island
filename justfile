default:
    @just --list

# Switch system configuration (e.g. just switch, just switch light, just switch kumo)
switch host="": (_rebuild "switch" host)

# Test system configuration without modifying bootloader
test host="": (_rebuild "test" host)

# Check all flake outputs and configurations
check:
    nix flake check

# Update custom packages in pkgs/ to their latest upstream versions
update-pkgs:
    #!/usr/bin/env bash
    set -euo pipefail
    pkgs=(
        "lxgw-neoxihei"
        "lxgw-zhisong"
        "mpv-handler"
        "xwayland-satellite"
        "qt6-cava-plugin"
        "persona-shell"
        "aptor"
        "grim"
    )
    for pkg in "${pkgs[@]}"; do
        echo "Updating $pkg..."
        nix shell nixpkgs#nix-update --command nix-update --flake --commit "$pkg" || true
    done

# Unified rebuild dispatcher
_rebuild action host:
    #!/usr/bin/env bash
    set -euo pipefail

    if [ -z "{{ host }}" ]; then
        sudo nixos-rebuild {{ action }} --flake .
        exit 0
    fi

    declare -A ips=(
        ["light"]="100.64.0.2"
        ["kumo"]="100.64.0.3"
    )

    target="${ips[{{ host }}]:-{{ host }}}"
    nixos-rebuild {{ action }} \
        --flake ".#{{ host }}" \
        --target-host "ib@${target}" \
        --sudo \
        --ask-sudo-password \
        --use-substitutes
