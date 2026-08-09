"""induo -- replace a running machine with NixOS by writing a disk image over it.

Three steps, each needing one more flag than the last:

  induo TARGET                          read the live network and disk layout
  induo TARGET --disk DEV               write the host file, kexec into a RAM
                                        stage, stop there
  induo TARGET --disk DEV --write       overwrite the disk and reboot

The target never runs Nix; the image is built here and streamed over ssh.
Everything before --write is reversible: the RAM stage does not touch the disk,
and its watchdog reboots back into the original system on its own.
"""

import argparse
import ipaddress
import json
import os
import socket
import subprocess
import time
from pathlib import Path

from rich.console import Console
from rich.table import Table

console = Console()
err = Console(stderr=True)

STAGE = os.environ.get("INDUO_STAGE", "@stage@")
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
    err.print(f"[bold red]induo:[/] {msg}")
    raise SystemExit(1)


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


def wait_port(host, port, timeout, what):
    deadline = time.monotonic() + timeout
    with console.status("") as status:
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
            status.update(f"waiting for {what} on {host}:{port} [dim]({left}s left)[/]")
            time.sleep(3)
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
    seen = {}
    for version in (4, 6):
        stack = p.get(f"v{version}")
        if not stack:
            continue
        var = seen.get(stack["mac"])
        if var is None:
            var = seen[stack["mac"]] = f"dev{version}"
            lines += [
                f'{var}=$(wait_dev {stack["mac"]})',
                f'ip link set "${var}" up',
            ]
        ip6 = "ip -6" if version == 6 else "ip"
        extra = " nodad" if version == 6 else ""
        lines += [
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
            '      systemd.network.networks."10-eth0" = {',
            f'        networkConfig.DHCP = "{dhcp}";',
            f"        address = [ {addresses} ];",
            "        routes = [",
            *routes,
            "        ];",
            "      };",
        ]

    body += [
        "      users.users.root.openssh.authorizedKeys.keys = [",
        *[f'        "{k}"' for k in keys],
        "      ];",
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


def find_repo():
    for d in [Path.cwd(), *Path.cwd().parents]:
        if (d / "flake.nix").exists() and (d / "modules/hosts").is_dir():
            return d
    fail("run this from inside the island checkout")


def gib(n):
    return f"{n / 1024**3:.1f} GiB"


def local_keys(paths):
    if paths:
        files = [Path(p) for p in paths]
    else:
        files = sorted((Path.home() / ".ssh").glob("*.pub"))
    keys = [f.read_text().strip() for f in files if f.is_file() and f.read_text().strip()]
    if not keys:
        fail("no public keys found, the new system would be unreachable")
    return keys


def show_probe(p):
    table = Table(show_header=False, box=None, padding=(0, 2, 0, 0))
    table.add_column(style="dim")
    table.add_column()
    table.add_row("firmware", p["firmware"])
    table.add_row("arch", p["arch"])
    table.add_row("memory", f"{p['mem_kb'] // 1024} MiB")
    for version in (4, 6):
        stack = p.get(f"v{version}")
        if stack:
            kind = "dhcp/ra" if stack["dynamic"] else "[yellow]static[/]"
            table.add_row(
                f"IPv{version}",
                f"{stack['address']} via {stack['gateway']} on {stack['dev']} ({kind})",
            )
    for dev, size in p["disks"]:
        mark = " [dim]<- current root[/]" if dev == p["root_disk"] else ""
        table.add_row("disk", f"{dev} {gib(size)}{mark}")
    console.print(table)


def build_image(repo, name):
    attr = f".#nixosConfigurations.{name}.config.system.build.diskImage"
    console.print(f"building [dim]{attr}[/]")
    # stderr stays on the terminal so nix's own progress output is visible;
    # only the store path comes back on stdout.
    proc = subprocess.run(
        ["nix", "build", "--no-link", "--print-out-paths", attr],
        cwd=repo,
        text=True,
        stdout=subprocess.PIPE,
    )
    if proc.returncode != 0:
        fail("nix build failed")
    out = Path(proc.stdout.strip().splitlines()[-1])
    image = out / "nixos.img.zst"
    if not image.exists():
        fail(f"{image} missing, did make-disk-image change its output name?")
    return image, int((out / "size").read_text().strip())


def stage_initrd(name, p, keys):
    config = Cpio()
    config.directory("induo")
    config.file("induo/net.sh", net_script(p), 0o755)
    config.directory("root")
    config.directory("root/.ssh")
    config.file("root/.ssh/authorized_keys", "\n".join(keys) + "\n", 0o600)

    path = Path(f"/tmp/induo-{name}.initrd")
    path.write_bytes(config.bytes() + Path(f"{STAGE}/initrd").read_bytes())
    return path


def main():
    ap = argparse.ArgumentParser(
        prog="induo",
        description="Replace a running machine with NixOS by writing a disk image over it.",
        epilog="Without --disk nothing is touched. Without --write the disk is not touched.",
    )
    ap.add_argument("target", help="ssh target of the machine to replace, e.g. root@1.2.3.4")
    ap.add_argument("--name", help="host name, defaults to the first label of the target")
    ap.add_argument("--disk", help="whole disk to overwrite, e.g. /dev/vda")
    ap.add_argument("--key", action="append", help="public key file, repeatable (default ~/.ssh/*.pub)")
    ap.add_argument("--regen", action="store_true", help="rewrite the host file even if it exists")
    ap.add_argument("--write", action="store_true", help="actually overwrite the disk")
    ap.add_argument("--timeout", type=int, default=1800, help="stage watchdog, seconds (default 1800)")
    args = ap.parse_args()

    repo = find_repo()
    target = args.target
    host = target.split("@")[-1]
    name = args.name or host.split(".")[0].replace("-", "_")
    if not name.isidentifier():
        fail(f"{name!r} is not usable as a nix attribute name, pass --name")

    with console.status(f"probing {target}"):
        p = probe(target)
    show_probe(p)

    if not p.get("v4") and not p.get("v6"):
        fail("could not determine any usable address, refusing to continue")

    if not args.disk:
        hint = p["root_disk"] or (p["disks"][0][0] if p["disks"] else "/dev/vda")
        console.print(f"\nnothing was touched. to continue: [bold]induo {target} --disk {hint}[/]")
        return
    if not any(args.disk == d for d, _ in p["disks"]):
        fail(f"{args.disk} is not one of the disks reported by {target}")

    path = repo / "modules/hosts" / name / "default.nix"
    if args.regen or not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(render_host(name, p, local_keys(args.key)))
        console.print(f"wrote [bold]{path.relative_to(repo)}[/]")
    else:
        console.print(f"keeping [bold]{path.relative_to(repo)}[/] [dim](--regen to rewrite)[/]")

    image, size = build_image(repo, name)
    disk_size = next(s for d, s in p["disks"] if d == args.disk)
    if disk_size < size:
        fail(f"{args.disk} is {gib(disk_size)}, image needs {gib(size)}")
    console.print(f"image {gib(size)} -> {args.disk} {gib(disk_size)}")

    initrd = stage_initrd(name, p, local_keys(args.key))
    with console.status(f"uploading stage to {target}:{REMOTE_DIR}"):
        ssh(target, f"mkdir -p {REMOTE_DIR}")
        scp(target, f"{STAGE}/kernel", f"{REMOTE_DIR}/kernel")
        scp(target, initrd, f"{REMOTE_DIR}/initrd")
        scp(target, f"{STAGE}/kexec", f"{REMOTE_DIR}/kexec")
    initrd.unlink()

    cmdline = f"console=tty0 console=ttyS0,115200 induo.timeout={args.timeout}"
    load = f"{REMOTE_DIR}/kexec -l {REMOTE_DIR}/kernel --initrd={REMOTE_DIR}/initrd --command-line='{cmdline}'"
    ssh(target, f"chmod +x {REMOTE_DIR}/kexec && {load}")
    ssh_detach(target, f"sleep 1; {REMOTE_DIR}/kexec -e")

    if not wait_port(host, STAGE_PORT, 300, "the induo stage"):
        fail("stage never came up; the watchdog will reboot it into the old system")
    console.print(f"stage is up: [dim]ssh -p {STAGE_PORT} {target}[/]")

    if not args.write:
        console.print(
            f"\ndisk untouched. add [bold]--write[/] to overwrite {args.disk}, "
            f"or wait {args.timeout}s for the watchdog to reboot into the old system"
        )
        return

    console.print(f"writing {args.disk}")
    argv = ssh_argv(target, STAGE_PORT, stage=True) + [target, f"induo-write {args.disk} {size}"]
    with image.open("rb") as f:
        if subprocess.run(argv, stdin=f).returncode != 0:
            fail("write failed; the stage is still up, fix and retry")

    ssh_detach(target, "sync; reboot -f", port=STAGE_PORT, stage=True)
    if wait_port(host, 22, 600, "NixOS"):
        console.print(f"[bold green]{name} is up:[/] ssh {target}")
    else:
        console.print("[yellow]no ssh yet[/]; check the provider console")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        console.print()
