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

# Update custom packages in pkgs/ to their latest upstream versions (e.g. just update-pkgs, just update pkgs, just update mpv-handler)
update-pkgs target="":
    #!/usr/bin/env bash
    set -euo pipefail
    export GIT_EDITOR="${GIT_EDITOR:-true}"

    update_one() {
        local pkg="$1"
        echo "Updating $pkg..."
        local extra_flags=()
        if [ "$pkg" = "sing-box" ]; then
            extra_flags+=(--version=unstable)
        fi
        # Try tag/release update first, fall back to tracking branch commits
        nix shell nixpkgs#nix-update --command nix-update --flake --commit "${extra_flags[@]}" "$pkg" 2>/dev/null \
            || nix shell nixpkgs#nix-update --command nix-update --flake --commit --version=branch "$pkg" 2>/dev/null \
            || true
    }

    if [ -n "{{ target }}" ] && [ "{{ target }}" != "pkgs" ] && [ "{{ target }}" != "all" ]; then
        update_one "{{ target }}"
    else
        for p in pkgs/*.nix pkgs/*/package.nix pkgs/*/default.nix; do
            [ -f "$p" ] || continue
            grep -qE "fetchFrom|fetchgit|fetchurl" "$p" || continue
            pkg="$(basename "$p" .nix)"
            [ "$pkg" = "package" ] || [ "$pkg" = "default" ] && pkg="$(basename "$(dirname "$p")")"
            update_one "$pkg"
        done
    fi

# Alias for update-pkgs
alias update := update-pkgs

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
