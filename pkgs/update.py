#!/usr/bin/env -S nix shell nixpkgs#python3 nixpkgs#nix-update --command python3
import json
import subprocess
import sys
from pathlib import Path

CONFIG_PATH = Path(__file__).parent / "update.json"


def main():
    with open(CONFIG_PATH) as f:
        packages: dict[str, list[str]] = json.load(f)

    targets = [t for t in sys.argv[1:] if t not in ("all", "pkgs")]
    if not targets:
        targets = list(packages.keys())

    for pkg in targets:
        flags = packages.get(pkg, [])
        print(f":: Updating {pkg}...")
        cmd = ["nix-update", "--flake", "--commit", *flags, pkg]
        subprocess.run(cmd)


if __name__ == "__main__":
    main()
