"""induo -- replace a running VPS with NixOS by writing a disk image over it.

Two commands' worth of work, driven interactively:

  probe    read the live network and disk layout off the target, before
           destroying it, and write modules/hosts/<name>/default.nix
  install  build the image locally, kexec the target into a small RAM stage,
           and stream the image onto its disk over ssh

The target never runs Nix. Everything up to the write is reversible: the RAM
stage does not touch the disk, and its watchdog reboots back into the original
system if nothing happens.
"""

import ipaddress
import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

STAGE = os.environ.get("INDUO_STAGE", "@stage@")
STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "induo/hosts.json"
REMOTE_DIR = "/var/tmp/induo"
STAGE_PORT = 2222
STATE_VERSION = "25.11"

SSH_BASE = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]
# The RAM stage generates a throwaway host key in tmpfs on every boot.
SSH_STAGE = SSH_BASE + [
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-o", "LogLevel=ERROR",
]


def fail(msg):
    print(f"induo: {msg}", file=sys.stderr)
    sys.exit(1)


class Cpio:
    """newc writer, so the per-host config archive can be built without a cpio
    binary on the operator's machine."""

    def __init__(self):
        self.buf = bytearray()
        self.ino = 1

    def _pad(self):
        self.buf += b"\0" * (-len(self.buf) % 4)

    def _entry(self, path, mode, data=b""):
        name = path.encode() + b"\0"
        fields = [self.ino, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(name), 0]
        self.buf += b"070701" + b"".join(b"%08X" % f for f in fields) + name
        self._pad()
        self.buf += data
        self._pad()
        self.ino += 1

    def directory(self, path):
        self._entry(path, 0o040755)

    def file(self, path, data, mode=0o644):
        self._entry(path, 0o100000 | mode, data.encode() if isinstance(data, str) else data)

    def bytes(self):
        end = Cpio()
        end.buf = bytearray(self.buf)
        end._entry("TRAILER!!!", 0)
        # Each concatenated archive must start on a 512-byte boundary; the
        # generic initrd follows this one.
        return bytes(end.buf) + b"\0" * (-len(end.buf) % 512)


def ssh_argv(target, port, stage=False, program="ssh"):
    opts = SSH_STAGE if stage else SSH_BASE
    flag = "-P" if program == "scp" else "-p"
    return [program, *opts, flag, str(port)]


def ssh(target, command, port=22, stage=False, check=True):
    argv = ssh_argv(target, port, stage) + [target, command]
    proc = subprocess.run(argv, capture_output=True, text=True)
    if check and proc.returncode != 0:
        fail(f"ssh {target}: {proc.stderr.strip() or proc.returncode}")
    return proc.stdout


def ssh_detach(target, command, port=22, stage=False):
    """For commands that kill the connection, such as kexec or reboot."""
    quoted = "'" + command.replace("'", "'\\''") + "'"
    argv = ssh_argv(target, port, stage) + [target, f"nohup sh -c {quoted} >/dev/null 2>&1 &"]
    subprocess.run(argv, capture_output=True, text=True)


def scp(target, local, remote, port=22, stage=False):
    argv = ssh_argv(target, port, stage, "scp") + [str(local), f"{target}:{remote}"]
    proc = subprocess.run(argv, capture_output=True, text=True)
    if proc.returncode != 0:
        fail(f"scp {local}: {proc.stderr.strip()}")


def wait_port(host, port, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for family in (socket.AF_INET6, socket.AF_INET):
            try:
                with socket.socket(family, socket.SOCK_STREAM) as s:
                    s.settimeout(4)
                    s.connect((host, port))
                    return True
            except OSError:
                pass
        left = int(deadline - time.monotonic())
        print(f"\r  waiting for {host}:{port} ({left}s left) ", end="", flush=True)
        time.sleep(3)
    print()
    return False


PROBE_SCRIPT = r"""
set -u
p() { echo "@@$1"; }
p link;     ip -j link 2>/dev/null || true
p addr;     ip -j addr 2>/dev/null || true
p route4;   ip -j route 2>/dev/null || true
p route6;   ip -j -6 route 2>/dev/null || true
p get4;     ip route get 1.1.1.1 2>/dev/null || true
p get6;     ip -6 route get 2606:4700:4700::1111 2>/dev/null || true
p rootsrc;  findmnt -n -o SOURCE / 2>/dev/null || awk '$2=="/"{print $1}' /proc/mounts
p firmware; if [ -d /sys/firmware/efi ]; then echo uefi; else echo bios; fi
p arch;     uname -m
p mem;      awk '/MemTotal/{print $2}' /proc/meminfo
p disks
for d in /sys/block/*; do
    n=$(basename "$d")
    case "$n" in loop*|ram*|zram*|dm-*|sr*) continue ;; esac
    s=$(cat "$d/size" 2>/dev/null || echo 0)
    [ "$s" -gt 0 ] || continue
    echo "$n $((s * 512))"
done
"""


def sections(out):
    result = {}
    key, body = None, []
    for line in out.splitlines():
        if line.startswith("@@"):
            if key:
                result[key] = "\n".join(body)
            key, body = line[2:].strip(), []
        else:
            body.append(line)
    if key:
        result[key] = "\n".join(body)
    return result


def load_json(text):
    try:
        return json.loads(text.strip() or "[]")
    except json.JSONDecodeError:
        return []


def token_after(text, word):
    parts = text.split()
    return parts[parts.index(word) + 1] if word in parts else ""


def pick_address(addrs, dev, family, src):
    """The interface's own prefix, preferring a permanent address over a
    privacy/temporary one."""
    entries = [
        a
        for link in addrs
        if link.get("ifname") == dev
        for a in link.get("addr_info", [])
        if a.get("family") == family and a.get("scope") == "global"
    ]
    ranked = sorted(entries, key=lambda a: (bool(a.get("temporary")), a.get("local") != src))
    if not ranked:
        return "", False
    best = ranked[0]
    return f"{best['local']}/{best['prefixlen']}", bool(best.get("dynamic"))


def default_gateway(routes, dev):
    for r in routes:
        if r.get("dst") == "default" and r.get("gateway") and r.get("dev") == dev:
            return r["gateway"]
    return ""


def probe(target):
    s = sections(ssh(target, PROBE_SCRIPT))
    links = load_json(s.get("link", ""))
    addrs = load_json(s.get("addr", ""))

    result = {
        "firmware": s.get("firmware", "").strip(),
        "arch": s.get("arch", "").strip(),
        "mem_kb": int(s.get("mem", "0").strip() or 0),
        "disks": [],
    }

    for line in s.get("disks", "").splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1].isdigit():
            result["disks"].append((f"/dev/{parts[0]}", int(parts[1])))

    root = s.get("rootsrc", "").strip().removeprefix("/dev/")
    candidates = [d for d, _ in result["disks"] if root.startswith(d.removeprefix("/dev/"))]
    result["root_disk"] = max(candidates, key=len) if candidates else ""

    for version, family, get_key, route_key in (
        (4, "inet", "get4", "route4"),
        (6, "inet6", "get6", "route6"),
    ):
        got = s.get(get_key, "")
        dev = token_after(got, "dev")
        if not dev:
            continue
        address, dynamic = pick_address(addrs, dev, family, token_after(got, "src"))
        gateway = default_gateway(load_json(s.get(route_key, "")), dev)
        if not address or not gateway:
            continue
        mac = next((link.get("address", "") for link in links if link.get("ifname") == dev), "")
        result[f"v{version}"] = {
            "dev": dev,
            "mac": mac,
            "address": address,
            "gateway": gateway,
            "dynamic": dynamic,
        }
    return result


def net_script(p):
    """Static configuration for the RAM stage, even on DHCP hosts: the lease we
    just read is valid for the few minutes the stage is alive, and this keeps a
    DHCP client out of the initrd entirely."""
    lines = [
        "set -eu",
        "",
        "wait_dev() {",
        "\tn=0",
        "\twhile [ $n -lt 30 ]; do",
        "\t\tfor d in /sys/class/net/*; do",
        '\t\t\tif [ "$(cat "$d/address" 2>/dev/null)" = "$1" ]; then',
        '\t\t\t\tbasename "$d"',
        "\t\t\t\treturn 0",
        "\t\t\tfi",
        "\t\tdone",
        "\t\tsleep 1",
        "\t\tn=$((n + 1))",
        "\tdone",
        '\techo "induo: no interface with MAC $1" >&2',
        "\treturn 1",
        "}",
        "",
    ]
    for version in (4, 6):
        stack = p.get(f"v{version}")
        if not stack:
            continue
        var = f"dev{version}"
        ip6 = "ip -6" if version == 6 else "ip"
        extra = " nodad" if version == 6 else ""
        lines += [
            f'{var}=$(wait_dev {stack["mac"]})',
            f'ip link set "${var}" up',
            f'{ip6} addr add {stack["address"]} dev "${var}"{extra}',
            # onlink is harmless when the gateway is on-link and required when
            # it is not, as with /32 layouts or an fe80:: gateway.
            f'{ip6} route add default via {stack["gateway"]} dev "${var}" onlink',
            "",
        ]
    return "\n".join(lines)


def render_host(name, p, keys):
    static = [v for v in ("v4", "v6") if p.get(v) and not p[v]["dynamic"]]
    body = []

    if static:
        dhcp = {("v4",): "ipv6", ("v6",): "ipv4"}.get(tuple(static), "no")
        addresses = " ".join(f'"{p[v]["address"]}"' for v in static)
        routes = []
        for v in static:
            onlink = not gateway_on_link(p[v]["address"], p[v]["gateway"])
            suffix = " GatewayOnLink = true;" if onlink else ""
            routes.append(f'          {{ Gateway = "{p[v]["gateway"]}";{suffix} }}')
        body += [
            '        systemd.network.networks."10-eth0" = {',
            f'          networkConfig.DHCP = "{dhcp}";',
            f"          address = [ {addresses} ];",
            "          routes = [",
            *routes,
            "          ];",
            "        };",
        ]

    body += [
        "        users.users.root.openssh.authorizedKeys.keys = [",
        *[f'          "{k}"' for k in keys],
        "        ];",
    ]

    return "\n".join(
        [
            "{ self, ... }:",
            "{",
            f"  hosts.{name} = {{",
            '    system = "x86_64-linux";',
            f'    stateVersion = "{STATE_VERSION}";',
            "    module = {",
            "      imports = with self.modules.nixos; [",
            "        vps",
            "        induo-image",
            "      ];",
            *body,
            "    };",
            "  };",
            "}",
            "",
        ]
    )


def gateway_on_link(address, gateway):
    try:
        return ipaddress.ip_address(gateway) in ipaddress.ip_interface(address).network
    except ValueError:
        return False


def load_state():
    if STATE.exists():
        return json.loads(STATE.read_text())
    return {}


def save_state(state):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")


def find_repo():
    for d in [Path.cwd(), *Path.cwd().parents]:
        if (d / "flake.nix").exists() and (d / "modules/hosts").is_dir():
            return d
    fail("run this from inside the island checkout")


def gib(n):
    return f"{n / 1024**3:.1f} GiB"


def ask(prompt, default=""):
    suffix = f" [{default}]" if default else ""
    return input(f"{prompt}{suffix}: ").strip() or default


def confirm(prompt):
    return input(f"{prompt} [y/N]: ").strip().lower() in ("y", "yes")


def local_keys():
    return sorted(
        p.read_text().strip()
        for p in (Path.home() / ".ssh").glob("*.pub")
        if p.is_file() and p.read_text().strip()
    )


def show_probe(p):
    print(f"  firmware  {p['firmware']}")
    print(f"  arch      {p['arch']}")
    print(f"  memory    {p['mem_kb'] // 1024} MiB")
    for version in (4, 6):
        stack = p.get(f"v{version}")
        if stack:
            kind = "dhcp/ra" if stack["dynamic"] else "static"
            print(f"  IPv{version}      {stack['address']} via {stack['gateway']} on {stack['dev']} ({kind})")
    for dev, size in p["disks"]:
        mark = "  <- current root" if dev == p["root_disk"] else ""
        print(f"  disk      {dev} {gib(size)}{mark}")


def new_host(repo, state):
    target = ask("ssh target (root@host)")
    if not target:
        return
    name = ask("name", target.split("@")[-1].split(".")[0])
    if not name.isidentifier():
        fail(f"{name!r} is not usable as a nix attribute name")

    print("probing...")
    p = probe(target)
    show_probe(p)

    if not p.get("v4") and not p.get("v6"):
        fail("could not determine any usable address, refusing to continue")

    disk = ask("\noverwrite which disk", p["root_disk"])
    if not any(disk == d for d, _ in p["disks"]):
        fail(f"{disk} is not one of the disks reported by the target")

    keys = local_keys()
    if not keys:
        fail("no public keys in ~/.ssh, the new system would be unreachable")
    print("\nauthorized keys for the new system:")
    for i, k in enumerate(keys, 1):
        print(f"  {i}) {k[:70]}")
    chosen = ask("pick (space separated)", "1")
    try:
        keys = [keys[int(i) - 1] for i in chosen.split()]
    except (ValueError, IndexError):
        fail("invalid selection")

    path = repo / "modules/hosts" / name / "default.nix"
    if path.exists() and not confirm(f"\n{path} exists, overwrite?"):
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(render_host(name, p, keys))
    print(f"wrote {path.relative_to(repo)}")

    state[name] = {"target": target, "disk": disk, "keys": keys}
    save_state(state)
    print(f"remembered {name} -> {target} {disk}")

    if confirm("\ninstall now?"):
        install(repo, name, state)


def build_image(repo, name):
    attr = f".#nixosConfigurations.{name}.config.system.build.diskImage"
    print(f"building {attr}")
    proc = subprocess.run(
        ["nix", "build", "--no-link", "--print-out-paths", attr],
        cwd=repo,
        text=True,
        capture_output=True,
    )
    if proc.returncode != 0:
        fail(f"nix build failed:\n{proc.stderr.strip()}")
    out = Path(proc.stdout.strip().splitlines()[-1])
    image = out / "nixos.img.zst"
    size = int((out / "size").read_text().strip())
    if not image.exists():
        fail(f"{image} missing, did make-disk-image change its output name?")
    return image, size


def install(repo, name, state):
    entry = state[name]
    target, disk = entry["target"], entry["disk"]
    host = target.split("@")[-1]

    # Never trust the remembered device: a reprovisioned VPS can rename it.
    print(f"checking {target}")
    p = probe(target)
    if not any(disk == d for d, _ in p["disks"]):
        print(f"induo: {disk} no longer exists on {target}", file=sys.stderr)
        show_probe(p)
        fail("re-probe this host before installing")
    if p["root_disk"] and p["root_disk"] != disk:
        print(f"warning: target now boots off {p['root_disk']}, not {disk}")
        if not confirm("continue anyway?"):
            return

    image, size = build_image(repo, name)
    disk_size = next(s for d, s in p["disks"] if d == disk)
    if disk_size < size:
        fail(f"{disk} is {gib(disk_size)}, image needs {gib(size)}")
    print(f"image {gib(size)} -> {disk} {gib(disk_size)}")

    config = Cpio()
    config.directory("induo")
    config.file("induo/net.sh", net_script(p), 0o755)
    config.directory("root")
    config.directory("root/.ssh")
    config.file("root/.ssh/authorized_keys", "\n".join(entry["keys"]) + "\n", 0o600)

    initrd = Path(f"/tmp/induo-{name}.initrd")
    initrd.write_bytes(config.bytes() + Path(f"{STAGE}/initrd").read_bytes())

    print(f"uploading stage to {target}:{REMOTE_DIR}")
    ssh(target, f"mkdir -p {REMOTE_DIR}")
    scp(target, f"{STAGE}/kernel", f"{REMOTE_DIR}/kernel")
    scp(target, initrd, f"{REMOTE_DIR}/initrd")
    scp(target, f"{STAGE}/kexec", f"{REMOTE_DIR}/kexec")
    initrd.unlink()

    if not confirm(f"\nkexec {target} into the induo stage?"):
        return

    cmdline = "console=tty0 console=ttyS0,115200 induo.timeout=1800"
    load = f"{REMOTE_DIR}/kexec -l {REMOTE_DIR}/kernel --initrd={REMOTE_DIR}/initrd --command-line='{cmdline}'"
    ssh(target, f"chmod +x {REMOTE_DIR}/kexec && {load}")
    print("kexec loaded, jumping")
    ssh_detach(target, f"sleep 1; {REMOTE_DIR}/kexec -e")

    if not wait_port(host, STAGE_PORT, 300):
        fail("stage never came up; the watchdog will reboot it into the old system")
    print("\nstage is up")

    print("writing image")
    argv = ssh_argv(target, STAGE_PORT, stage=True) + [target, f"induo-write {disk} {size}"]
    with image.open("rb") as f:
        if subprocess.run(argv, stdin=f).returncode != 0:
            fail("write failed; the stage is still up, fix and retry")

    ssh_detach(target, "sync; reboot -f", port=STAGE_PORT, stage=True)
    print("rebooting into NixOS")
    if wait_port(host, 22, 600):
        print(f"\n{name} is up: ssh {target}")
    else:
        print("\nno ssh yet; check the provider console")


def host_menu(repo, name, state):
    entry = state[name]
    print(f"\n{name}  {entry['target']}  {entry['disk']}")
    print("  1) install")
    print("  2) re-probe")
    print("  3) forget")
    choice = ask("action", "1")
    if choice == "1":
        install(repo, name, state)
    elif choice == "2":
        p = probe(entry["target"])
        show_probe(p)
        path = repo / "modules/hosts" / name / "default.nix"
        if confirm(f"rewrite {path.relative_to(repo)}?"):
            path.write_text(render_host(name, p, entry["keys"]))
    elif choice == "3":
        del state[name]
        save_state(state)


def main():
    repo = find_repo()
    state = load_state()
    while True:
        names = sorted(state)
        print()
        for i, name in enumerate(names, 1):
            print(f"  {i}) {name:10} {state[name]['target']:24} {state[name]['disk']}")
        print("  n) new host")
        print("  q) quit")
        choice = ask("\n>")
        if choice == "q":
            return
        if choice == "n":
            new_host(repo, state)
        elif choice.isdigit() and 1 <= int(choice) <= len(names):
            host_menu(repo, names[int(choice) - 1], state)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print()
