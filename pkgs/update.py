#!/usr/bin/env -S nix shell nixpkgs#python3 nixpkgs#nix-prefetch-git --command python3
"""Declarative, decoupled sources.json updater for island packages.

This script has no hardcoded package names or URLs; it dispatches
purely based on the declarative 'type' attribute defined in sources.json.
"""

import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

PKGS_DIR = Path(__file__).parent
SOURCES_PATH = PKGS_DIR / "sources.json"
REPO_ROOT = PKGS_DIR.parent


def github_api_get(endpoint: str):
    """Fetch GitHub REST API endpoint, utilizing GITHUB_TOKEN if set."""
    url = f"https://api.github.com/{endpoint}"
    headers = {"User-Agent": "island-updater"}
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)


def prefetch_file(url: str) -> str:
    """Compute sha256 SRI hash of a remote file via modern nix command."""
    out = subprocess.check_output(
        ["nix", "store", "prefetch-file", "--json", url], text=True
    )
    return json.loads(out)["hash"]


def prefetch_git(url: str, rev: str) -> dict:
    """Fetch git repository revision and compute SRI hash."""
    cmd = ["nix-prefetch-git", "--quiet", "--url", url, "--rev", rev]
    out = subprocess.check_output(cmd, text=True)
    return json.loads(out)


def get_git_ls_remote(url: str, branch: str) -> str:
    """Query git remote for the latest revision SHA of a branch."""
    out = subprocess.check_output(["git", "ls-remote", url, f"refs/heads/{branch}"], text=True)
    parts = out.strip().split()
    if not parts:
        raise RuntimeError(f"Branch '{branch}' not found for {url}")
    return parts[0]


# --- Generic Handlers ---


def handle_github(name: str, entry: dict) -> tuple[bool, str, str]:
    """Track the latest commit on a GitHub repository branch."""
    src = entry["src"]
    owner = src["owner"]
    repo = src["repo"]
    branch = entry.get("branch", "master")
    git_url = f"https://github.com/{owner}/{repo}.git"

    latest_rev = get_git_ls_remote(git_url, branch)
    prev_rev = src.get("rev", "")

    if latest_rev == prev_rev:
        return False, prev_rev[:7], latest_rev[:7]

    print(f"  Fetching {name} commit {latest_rev[:7]}...")
    info = prefetch_git(git_url, latest_rev)
    date_str = info.get("date", "")[:10]

    entry["version"] = f"0-unstable-{date_str}" if date_str else "0-unstable"
    src["rev"] = latest_rev
    src["hash"] = info["hash"]

    return True, prev_rev[:7], latest_rev[:7]


def handle_git(name: str, entry: dict) -> tuple[bool, str, str]:
    """Track the latest commit on a generic Git repository (GitLab, Codeberg, etc.)."""
    src = entry["src"]
    git_url = src["url"]
    branch = entry.get("branch", "master")

    latest_rev = get_git_ls_remote(git_url, branch)
    prev_rev = src.get("rev", "")

    if latest_rev == prev_rev:
        return False, prev_rev[:7], latest_rev[:7]

    print(f"  Fetching {name} commit {latest_rev[:7]}...")
    info = prefetch_git(git_url, latest_rev)
    src["rev"] = latest_rev
    src["hash"] = info["hash"]

    return True, prev_rev[:7], latest_rev[:7]


def handle_github_release(name: str, entry: dict) -> tuple[bool, str, str]:
    """Track the latest non-prerelease source code on a GitHub repository."""
    src = entry["src"]
    owner = src["owner"]
    repo = src["repo"]

    releases = github_api_get(f"repos/{owner}/{repo}/releases")
    latest_release = next((r for r in releases if not r.get("prerelease") and not r.get("draft")), None)
    if not latest_release:
        raise RuntimeError(f"No release found for {owner}/{repo}")

    latest_tag = latest_release["tag_name"]
    clean_version = latest_tag.lstrip("v")
    prev_version = entry.get("version", "")

    if clean_version == prev_version:
        return False, prev_version, clean_version

    print(f"  Fetching {name} release {latest_tag}...")
    git_url = f"https://github.com/{owner}/{repo}.git"
    info = prefetch_git(git_url, f"refs/tags/{latest_tag}")

    entry["version"] = clean_version
    src["rev"] = info["rev"]
    src["hash"] = info["hash"]

    return True, prev_version, clean_version


def handle_github_release_binary(name: str, entry: dict) -> tuple[bool, str, str]:
    """Track multi-architecture precompiled binaries from GitHub Releases."""
    owner = entry["owner"]
    repo = entry["repo"]
    pattern = entry.get("asset_pattern", "{name}-{arch}")

    releases = github_api_get(f"repos/{owner}/{repo}/releases")
    latest_tag = None
    for r in releases:
        if not r.get("prerelease") and not r.get("draft"):
            tag = r.get("tag_name")
            if tag and tag != "twilight":
                latest_tag = tag
                break

    if not latest_tag:
        raise RuntimeError(f"No suitable release found for {owner}/{repo}")

    prev_tag = entry.get("version", "")
    if latest_tag == prev_tag:
        return False, prev_tag, latest_tag

    print(f"  Prefetching {name} {latest_tag} binaries...")
    # Find all arch targets (keys matching *-linux or *-darwin)
    arch_keys = [k for k in entry.keys() if "-" in k and not k.startswith("_")]

    for arch_key in arch_keys:
        arch_part = arch_key.split("-")[0]
        filename = pattern.replace("{arch}", arch_part).replace("{version}", latest_tag)
        url = f"https://github.com/{owner}/{repo}/releases/download/{latest_tag}/{filename}"
        hash_val = prefetch_file(url)
        entry[arch_key] = {
            "url": url,
            "hash": hash_val,
        }

    entry["version"] = latest_tag
    return True, prev_tag, latest_tag


HANDLERS = {
    "github": handle_github,
    "git": handle_git,
    "github-release": handle_github_release,
    "github-release-binary": handle_github_release_binary,
}


def read_sources() -> dict:
    with open(SOURCES_PATH) as f:
        return json.load(f)


def main():
    raw_args = sys.argv[1:]
    commit = "--commit" in raw_args
    raw_args = [a for a in raw_args if not a.startswith("--")]

    sources = read_sources()
    targets = [t for t in raw_args if t in sources]
    if not targets:
        targets = list(sources.keys())

    changes = []
    failed = []

    for name in targets:
        entry = sources.get(name)
        if not entry:
            continue

        pkg_type = entry.get("type")
        handler = HANDLERS.get(pkg_type)
        if not handler:
            print(f":: Skipping {name} (unknown type '{pkg_type}')")
            continue

        print(f":: Checking {name} ({pkg_type})...")
        try:
            changed, old_ver, new_ver = handler(name, entry)
            if changed:
                changes.append((name, old_ver, new_ver))
                print(f"   -> Updated: {old_ver} -> {new_ver}")
            else:
                print(f"   -> Up to date ({old_ver})")
        except Exception as e:
            print(f"   -> Error: {e}")
            failed.append(name)

    # Save updated sources.json
    with open(SOURCES_PATH, "w") as f:
        json.dump(sources, f, indent=2)
        f.write("\n")

    changelog_lines = []
    for name, old_ver, new_ver in changes:
        changelog_lines.append(f"- **{name}**: `{old_ver}` → `{new_ver}`")

    if changelog_lines:
        changelog_text = "\n".join(changelog_lines)
        (REPO_ROOT / "changelog.md").write_text(changelog_text + "\n")
        print("\nChanges:")
        print(changelog_text)

        if commit:
            subprocess.run(["git", "add", str(SOURCES_PATH)], cwd=REPO_ROOT, check=True)
            msg = "chore(pkgs): update " + ", ".join(f"{n} ({new})" for n, _, new in changes)
            subprocess.run(["git", "commit", "-m", msg], cwd=REPO_ROOT, check=True)
            print(f"\nCommitted: {msg}")
    else:
        print("\nAll packages are up to date.")
        changelog_file = REPO_ROOT / "changelog.md"
        if changelog_file.exists():
            changelog_file.unlink()

    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
