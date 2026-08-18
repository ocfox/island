default:
    @just --list

# Switch system configuration (e.g. just switch, just switch light, just switch kumo)
switch host="": (_rebuild "switch" host)

# Test system configuration without modifying bootloader
test host="": (_rebuild "test" host)

# Check all flake outputs and configurations
check:
    nix flake check

# Seal secrets for all hosts
seal *args:
    nix run .#kix-seal -- {{ args }}

# Edit or create an encrypted secret (e.g. just edit secrets/test.age)
edit file *args:
    nix run .#kix-edit -- {{ file }} {{ args }}

# Update custom packages in pkgs/ (e.g. just update, just update sing-box)
update *args:
    ./pkgs/update.py {{ args }}

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
