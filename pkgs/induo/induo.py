#!/usr/bin/env python3
"""induo: deploy a NixOS flake configuration to any remote Linux machine in RAM."""

import argparse
import getpass
import io
import json
import os
import socket
import subprocess
import threading
import time
from pathlib import Path

from rich.console import Console
from rich.progress import (
    BarColumn,
    DownloadColumn,
    Progress,
    TextColumn,
    TimeRemainingColumn,
    TransferSpeedColumn,
)
from rich.table import Table

console = Console(highlight=False)
err = Console(stderr=True, highlight=False)

STAGE = os.environ.get("INDUO_STAGE", "@stage@")
REMOTE_DIR = "/var/tmp/induo"
SSH_OPTS = [
    "-o", "ConnectTimeout=10",
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-o", "BatchMode=yes",
]


def fail(msg: str):
    err.print(f"[bold red]induo:[/] {msg}")
    raise SystemExit(1)


def find_repo() -> Path:
    p = Path.cwd()
    while p != p.parent:
        if (p / "flake.nix").exists():
            return p
        p = p.parent
    fail("could not find flake.nix in current directory or any parent")


class Target:
    def __init__(self, target: str, port: int = 22):
        self.raw = target
        self.port = port
        self.user, _, self.host = target.rpartition("@") if "@" in target else ("", "", target)
        self.host = self.host.strip("[]")
        self.dest = f"{self.user}@{self.host}" if self.user else self.host
        self.sudo_pw: str | None = None
        self._checked_sudo = False

    def argv(self, tool: str = "ssh") -> list[str]:
        p = ["-P" if tool == "scp" else "-p", str(self.port)] if self.port != 22 else []
        return [tool, *SSH_OPTS, *p, self.dest]

    def ensure_sudo(self):
        if self._checked_sudo or not self.user or self.user == "root":
            return
        self._checked_sudo = True
        proc = subprocess.run(self.argv() + ["sudo -n true"], capture_output=True, text=True, check=False)
        if proc.returncode != 0:
            self.sudo_pw = getpass.getpass(f"induo: sudo password for {self.dest}: ")
            pw_check = subprocess.run(
                self.argv() + ["sudo -S -p '' true"],
                input=self.sudo_pw + "\n",
                capture_output=True,
                text=True,
                check=False,
            )
            if pw_check.returncode != 0:
                fail("incorrect sudo password")

    def run(self, cmd: str, check: bool = True, sudo: bool = False) -> str:
        if sudo and self.user and self.user != "root":
            self.ensure_sudo()
            quoted_cmd = "'" + cmd.replace("'", "'\\''") + "'"
            if self.sudo_pw:
                proc = subprocess.run(
                    self.argv() + [f"sudo -S -p '' sh -c {quoted_cmd}"],
                    input=self.sudo_pw + "\n",
                    capture_output=True,
                    text=True,
                    check=False,
                )
            else:
                proc = subprocess.run(self.argv() + [f"sudo sh -c {quoted_cmd}"], capture_output=True, text=True, check=False)
        else:
            proc = subprocess.run(self.argv() + [cmd], capture_output=True, text=True, check=False)

        if check and proc.returncode != 0:
            fail(f"ssh {self.raw}: {proc.stderr.strip() or proc.stdout.strip() or f'exit code {proc.returncode}'}")
        return proc.stdout

    def pipe(self, data: bytes | Path, remote_file: str):
        payload = data if isinstance(data, bytes) else data.read_bytes()
        proc = subprocess.run(self.argv() + [f"cat > '{remote_file}'"], input=payload, capture_output=True, check=False)
        if proc.returncode != 0:
            fail(f"pipe to {remote_file}: {proc.stderr.decode().strip()}")

    def detach(self, cmd: str, sudo: bool = False):
        if sudo and self.user and self.user != "root":
            self.ensure_sudo()
            quoted_cmd = "'" + cmd.replace("'", "'\\''") + "'"
            if self.sudo_pw:
                quoted_pw = "'" + self.sudo_pw.replace("'", "'\\''") + "'"
                cmd_to_run = f"nohup sh -c 'echo {quoted_pw} | sudo -S -p \"\" {quoted_cmd}' </dev/null >/dev/null 2>&1 &"
            else:
                cmd_to_run = f"nohup sh -c 'sudo {quoted_cmd}' </dev/null >/dev/null 2>&1 &"
        else:
            quoted = "'" + cmd.replace("'", "'\\''") + "'"
            cmd_to_run = f"nohup sh -c {quoted} </dev/null >/dev/null 2>&1 &"
        subprocess.run(self.argv() + [cmd_to_run], capture_output=True, check=False)

    def is_stage(self) -> int:
        for p in (22, 2222):
            try:
                with socket.create_connection((self.host, p), timeout=1.5) as s:
                    if s.recv(1024).startswith(b"SSH-"):
                        test_target = Target(f"root@{self.host}", port=p)
                        if subprocess.run(test_target.argv() + ["test -f /run/induo-stage"], capture_output=True, check=False).returncode == 0:
                            return p
            except OSError:
                pass
        return 0


def wait_port(host: str, port: int, timeout: int, what: str) -> bool:
    deadline = time.monotonic() + timeout
    with console.status("") as status:
        while time.monotonic() < deadline:
            try:
                with socket.create_connection((host, port), timeout=2.0) as s:
                    if s.recv(1024).startswith(b"SSH-"):
                        return True
            except OSError:
                pass
            status.update(f"waiting for {what} on {host}:{port} [dim]({int(deadline - time.monotonic())}s left)[/]")
            time.sleep(3)
    return False


PROBE_SH = r"""
set -u
echo "{"
echo '  "firmware": "'$( [ -d /sys/firmware/efi ] && echo uefi || echo bios )'",'
echo '  "arch": "'$(uname -m)'",'
echo '  "memory_kib": '$(awk '/MemTotal/{print $2}' /proc/meminfo || echo 0)','
echo '  "rootsrc": "'$(findmnt -n -o SOURCE / 2>/dev/null || awk '$2=="/"{print $1}' /proc/mounts)'",'
echo '  "link": '$(ip -j link 2>/dev/null || echo '[]')','
echo '  "addr": '$(ip -j addr 2>/dev/null || echo '[]')','
echo '  "r4": '$(ip -j route 2>/dev/null || echo '[]')','
echo '  "r6": '$(ip -j -6 route 2>/dev/null || echo '[]')','
echo '  "get4": "'$(ip route get 1.1.1.1 2>/dev/null || true)'",'
echo '  "get6": "'$(ip -6 route get 2606:4700:4700::1111 2>/dev/null || true)'",'
echo '  "disks": ['
first=1
for d in /sys/block/*; do
  n=$(basename "$d")
  case "$n" in loop*|ram*|zram*|sr*|dm-*) continue ;; esac
  sz=$(cat "$d/size" 2>/dev/null || echo 0)
  [ "$sz" -gt 0 ] || continue
  [ "$first" = 1 ] && first=0 || echo ","
  echo '    ["/dev/'$n'", '$((sz * 512))']'
done
echo '  ]'
echo "}"
"""


def parse_probe(raw: str) -> dict:
    try:
        raw_json = json.loads(raw.strip())
    except json.JSONDecodeError:
        fail("failed to parse probe json output")

    links = {link.get("ifname"): link.get("address", "") for link in raw_json.get("link", [])}
    addrs = raw_json.get("addr", [])
    disks = raw_json.get("disks", [])
    rootsrc = raw_json.get("rootsrc", "")
    root_disk = next((dev for dev, _ in disks if rootsrc.startswith(dev)), (disks[0][0] if disks else "/dev/vda"))

    def gw(routes, dev):
        return next((r.get("gateway", "") for r in routes if r.get("dst") == "default" and r.get("dev") == dev), "")

    def find_ip(family, routes, got_str):
        tokens = got_str.split()
        if "dev" not in tokens:
            return None
        dev = tokens[tokens.index("dev") + 1]
        gateway = gw(routes, dev)
        for entry in addrs:
            if entry.get("ifname") != dev:
                continue
            for info in entry.get("addr_info", []):
                if info.get("family") == family and info.get("scope") != "link" and info.get("local"):
                    return {
                        "dev": dev,
                        "mac": links.get(dev, ""),
                        "address": f"{info['local']}/{info.get('prefixlen', 32 if family == 'inet' else 128)}",
                        "gateway": gateway,
                        "dynamic": bool(info.get("dynamic")),
                    }
        return None

    return {
        "firmware": raw_json.get("firmware", "bios"),
        "arch": raw_json.get("arch", "x86_64"),
        "memory_kib": raw_json.get("memory_kib", 0),
        "disks": disks,
        "root_disk": root_disk,
        "v4": find_ip("inet", raw_json.get("r4", []), raw_json.get("get4", "")),
        "v6": find_ip("inet6", raw_json.get("r6", []), raw_json.get("get6", "")),
    }


def show_probe(p: dict):
    tbl = Table.grid(padding=(0, 2))
    tbl.add_column(style="dim")
    tbl.add_column()
    tbl.add_row("firmware", p["firmware"])
    tbl.add_row("arch", p["arch"])
    tbl.add_row("memory", f"{p['memory_kib'] // 1024} MiB")
    for v in (4, 6):
        if s := p.get(f"v{v}"):
            tbl.add_row(f"IPv{v}", f"{s['address']} via {s['gateway']} on {s['dev']}{' (dhcp)' if s['dynamic'] else ' (static)'}")
    for d, sz in p["disks"]:
        tbl.add_row("disk", f"{d} {sz / (1024 ** 3):.1f} GiB{' [bold green]<- root[/]' if d == p['root_disk'] else ''}")
    console.print(tbl)


def render_host(name: str, p: dict, disk: str) -> tuple[str, str]:
    pin_addrs = [p[v]["address"] for v in ("v4", "v6") if p.get(v) and (not p[v]["dynamic"] or p[v]["address"].endswith("/128"))]
    routes = [f'          {{ Gateway = "{p[v]["gateway"]}"; GatewayOnLink = true; }}' for v in ("v4", "v6") if p.get(v) and not p[v]["dynamic"]]
    dhcp = {("v4",): "ipv6", ("v6",): "ipv4"}.get(tuple(v for v in ("v4", "v6") if p.get(v) and not p[v]["dynamic"]), "yes") if pin_addrs else "yes"

    net_block = []
    if pin_addrs or routes or dhcp != "yes":
        net_block = ['        systemd.network.networks."10-eth0" = {']
        if dhcp != "yes":
            net_block.append(f'          networkConfig.DHCP = "{dhcp}";')
        if pin_addrs:
            net_block.append(f'          address = [ {" ".join(f"{chr(34)}{a}{chr(34)}" for a in pin_addrs)} ];')
        if routes:
            net_block += ["          routes = [", *routes, "          ];"]
        net_block.append("        };")

    net_body = ("\n" + "\n".join(net_block)) if net_block else ""
    default_nix = f"""{{ self, ... }}:
{{
  hosts.{name} = {{
    system = "{p['arch']}-linux";
    stateVersion = "{STATE_VERSION}";
    module =
      {{ ... }}:
      {{
        imports = with self.modules.nixos; [
          vps
          disko
        ];

        boot.loader = {{
          grub.enable = false;
          efi.canTouchEfiVariables = false;
          limine = {{
            enable = true;
            efiSupport = true;
            efiInstallAsRemovable = true;
            biosSupport = true;
            biosDevice = "{disk}";
            partitionIndex = 1;
          }};
        }};{net_body}
      }};
  }};
}}
"""

    disko_nix = f"""{{
  flake.modules.nixos.{name}.disko.devices = {{
    disk.disk1 = {{
      type = "disk";
      device = "{disk}";
      content = {{
        type = "gpt";
        partitions = {{
          MBR = {{
            type = "EF02";
            size = "1M";
            priority = 1;
          }};
          ESP = {{
            type = "EF00";
            size = "500M";
            content = {{
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            }};
          }};
          root = {{
            size = "100%";
            content = {{
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {{
                "/rootfs" = {{
                  mountpoint = "/";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                    "x-systemd.growfs"
                  ];
                }};
                "/nix" = {{
                  mountpoint = "/nix";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                }};
                "/home" = {{
                  mountpoint = "/home";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                }};
              }};
            }};
          }};
        }};
      }};
    }};
  }};
}}
"""
    return default_nix, disko_nix


def resolve_keys(repo: Path, name: str, explicit_keys: list[str] | None) -> list[str]:
    if explicit_keys:
        return [Path(k).read_text().strip() for k in explicit_keys]
    expr = f""".#nixosConfigurations.{name}.config"""
    apply = r"c: (c.users.users.${c.my.name}.openssh.authorizedKeys.keys or []) ++ (c.users.users.root.openssh.authorizedKeys.keys or [])"
    proc = subprocess.run(["nix", "eval", expr, "--apply", apply, "--json"], cwd=repo, capture_output=True, text=True, check=False)
    if proc.returncode == 0:
        try:
            return json.loads(proc.stdout)
        except json.JSONDecodeError:
            pass
    local_pubs = list(Path.home().glob(".ssh/*.pub"))
    if local_pubs:
        return [p.read_text().strip() for p in local_pubs]
    fail("no authorized keys found in nixos config or ~/.ssh/*.pub")


def build_image(repo: Path, name: str) -> tuple[Path, int, bool]:
    attr_disko = f".#nixosConfigurations.{name}.config.system.build.diskoImages"
    console.print(f"[dim]building {attr_disko}[/]")
    proc = subprocess.run(["nix", "build", attr_disko, "--no-link", "--print-out-paths"], cwd=repo, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        fail(f"nix build {attr_disko} failed: {proc.stderr}")

    out = Path(proc.stdout.strip())
    candidates = list(out.glob("*.zst")) + list(out.glob("*.raw")) + list(out.glob("*.img"))
    if not candidates:
        fail(f"no disk image found in {out}")

    img = candidates[0]
    is_compressed = img.name.endswith(".zst")
    size = int((out / "size").read_text().strip()) if (out / "size").exists() else img.stat().st_size
    return img, size, is_compressed


def cpio_entry(name: str, body: bytes, mode: int) -> bytes:
    nb = name.encode("ascii") + b"\0"
    hdr = f"070701{0:08x}{mode:08x}{0:08x}{0:08x}{1:08x}{int(time.time()):08x}{len(body):08x}{0:08x}{0:08x}{0:08x}{0:08x}{len(nb):08x}{0:08x}".encode("ascii")

    def pad(b: bytes) -> bytes:
        return b + b"\0" * ((4 - len(b) % 4) % 4)

    return pad(hdr + nb) + pad(body)


def make_stage_initrd(keys: list[str], p: dict) -> bytes:
    net_cmds = ["#!/bin/sh", "ip link set lo up"]
    for v in (4, 6):
        if s := p.get(f"v{v}"):
            ip_cmd = "ip -6" if v == 6 else "ip"
            net_cmds += [
                f'for d in /sys/class/net/*; do [ "$(cat "$d/address" 2>/dev/null)" = "{s["mac"]}" ] && dev=$(basename "$d"); done',
                'dev=${dev:-eth0}',
                'ip link set "$dev" up 2>/dev/null || true',
                'udhcpc -i "$dev" -b -s /etc/udhcpc.script 2>/dev/null || true',
                f'{ip_cmd} addr add {s["address"]} dev "$dev" 2>/dev/null || true',
                f'{ip_cmd} route add {s["gateway"]} dev "$dev" 2>/dev/null || true',
                f'{ip_cmd} route add default via {s["gateway"]} dev "$dev" onlink 2>/dev/null || true',
            ]
    buf = io.BytesIO()
    buf.write(cpio_entry("induo", b"", 0o040755))
    buf.write(cpio_entry("induo/net.sh", ("\n".join(net_cmds) + "\n").encode(), 0o100755))
    buf.write(cpio_entry("root", b"", 0o040700))
    buf.write(cpio_entry("root/.ssh", b"", 0o040700))
    buf.write(cpio_entry("root/.ssh/authorized_keys", ("\n".join(keys) + "\n").encode(), 0o100600))
    buf.write(cpio_entry("TRAILER!!!", b"", 0))
    buf.write(Path(f"{STAGE}/initrd").read_bytes())
    return buf.getvalue()


def deploy_and_boot_stage(target: Target, p: dict, initrd: bytes, timeout: int):
    k_path, g_path = Path(f"{STAGE}/kernel"), Path(f"{STAGE}/grub.efi")
    total_sz = k_path.stat().st_size + len(initrd) + (g_path.stat().st_size if g_path.exists() else 0)
    console.print(f"stage [bold]{total_sz / (1024 * 1024):.1f} MiB[/] -> {target.raw}:{REMOTE_DIR}")

    target.run(f"rm -rf {REMOTE_DIR} && mkdir -p {REMOTE_DIR} && chown -R $USER:$USER {REMOTE_DIR}", sudo=True)
    target.pipe(k_path, f"{REMOTE_DIR}/kernel")
    target.pipe(initrd, f"{REMOTE_DIR}/initrd")
    if g_path.exists():
        target.pipe(g_path, f"{REMOTE_DIR}/grub.efi")

    boot_sh = f"""set -e
mkdir -p /boot/induo /induo
cp -f {REMOTE_DIR}/kernel /boot/induo/kernel && cp -f {REMOTE_DIR}/initrd /boot/induo/initrd
cp -f {REMOTE_DIR}/kernel /induo/kernel 2>/dev/null || true && cp -f {REMOTE_DIR}/initrd /induo/initrd 2>/dev/null || true
if [ -d /sys/firmware/efi ]; then
  for d in $(findmnt -t fat,vfat -n -o TARGET 2>/dev/null | grep -Ex '/efi|/boot/efi|/boot') /boot/efi /boot/EFI /efi /boot; do
    [ -d "$d" ] || continue
    part=$(findmnt -n -o SOURCE "$d" 2>/dev/null || df "$d" | awk 'NR==2{{print $1}}')
    [ -b "$part" ] || continue
    disk=$(lsblk -rn --inverse "$part" 2>/dev/null | awk '$6=="disk"{{print $1}}' | head -1)
    [ -z "$disk" ] && disk=$(echo "$part" | sed -E 's/p?[0-9]+$//' | sed 's|/dev/||')
    pnum=$(echo "$part" | grep -oE '[0-9]+$')
    mkdir -p "$d/EFI/induo" && cp -f {REMOTE_DIR}/grub.efi "$d/EFI/induo/grub.efi"
    for b in $(efibootmgr 2>/dev/null | awk '/induo/{{print $1}}' | tr -d 'Boot*'); do efibootmgr -B -b "$b" >/dev/null 2>&1 || true; done
    if efibootmgr -c -d "/dev/$disk" -p "$pnum" -L "induo" -l "\\EFI\\induo\\grub.efi" >/dev/null 2>&1; then
      b=$(efibootmgr 2>/dev/null | awk '/induo/{{print $1}}' | tr -d 'Boot*' | head -1)
      [ -n "$b" ] && efibootmgr -n "$b" >/dev/null 2>&1 && echo "BOOT_EFI" && exit 0
    fi
  done
fi
cmdline="console=tty0 console=ttyS0,115200n8 console=ttyAMA0,115200n8 earlycon panic=10 net.ifnames=0 induo.timeout={timeout}"
printf 'set timeout=3\\nmenuentry "induo-stage" {{\\n  search --no-floppy --file --set=root /boot/induo/kernel\\n  linux ($root)/boot/induo/kernel '"$cmdline"'\\n  initrd ($root)/boot/induo/initrd\\n}}\\n' | tee /boot/grub2/custom.cfg /boot/grub/custom.cfg /etc/grub.d/40_custom >/dev/null 2>&1 || true
grub2-reboot "induo-stage" 2>/dev/null || grub-reboot "induo-stage" 2>/dev/null || true
echo "BOOT_GRUB"
"""
    mode = target.run(boot_sh, sudo=True).strip().splitlines()[-1]
    console.print(f"[dim]rebooting via {mode.lower()}...[/]")
    target.detach("reboot -f || reboot", sudo=True)


def write_disk(target: Target, image: Path, disk: str, is_compressed: bool = False):
    img_size = image.stat().st_size
    target.run(f"modprobe sd_mod 2>/dev/null || true; mdev -s 2>/dev/null || true; [ -b {disk} ] || (rm -f {disk}; mknod {disk} b 8 0 2>/dev/null || true); touch /run/active")

    ssh_cmd = target.argv() + [
        "-c", "aes128-gcm@openssh.com,chacha20-poly1305@openssh.com,aes128-ctr",
        "-o", "Compression=no", "-o", "IPQoS=throughput",
        f"zstd -dc | dd of={disk} bs=4M conv=fsync status=none",
    ]

    ssh_proc = subprocess.Popen(ssh_cmd, stdin=subprocess.PIPE, stderr=subprocess.PIPE)
    zstd_proc = None
    t = None

    if not is_compressed:
        zstd_proc = subprocess.Popen(["zstd", "-T0", "-6"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        def pump():
            try:
                while chunk := zstd_proc.stdout.read(1024 * 1024):
                    ssh_proc.stdin.write(chunk)
            except (BrokenPipeError, OSError):
                pass
            finally:
                try:
                    ssh_proc.stdin.close()
                except OSError:
                    pass

        t = threading.Thread(target=pump, daemon=True)
        t.start()
        feeder = zstd_proc.stdin
    else:
        feeder = ssh_proc.stdin

    progress = Progress(
        TextColumn("[bold cyan]{task.description}"),
        BarColumn(bar_width=40),
        "[progress.percentage]{task.percentage:>3.0f}%",
        DownloadColumn(),
        TransferSpeedColumn(),
        TimeRemainingColumn(),
        console=console,
    )

    start_time = time.monotonic()
    with progress, image.open("rb") as f:
        task = progress.add_task(f"writing to {disk}", total=img_size)
        while chunk := f.read(1024 * 1024):
            try:
                feeder.write(chunk)
                progress.advance(task, len(chunk))
            except (BrokenPipeError, OSError) as e:
                err_msg = ssh_proc.stderr.read().decode().strip() if ssh_proc.stderr else str(e)
                fail(f"stream failed: {err_msg}")

        try:
            feeder.close()
        except OSError:
            pass

        if zstd_proc:
            zstd_proc.wait()
            if t:
                t.join()
        if (ret := ssh_proc.wait()) != 0:
            fail(f"remote dd failed (code {ret}): {ssh_proc.stderr.read().decode().strip()}")

    console.print(f"[bold green]disk write complete:[/] {disk} in {time.monotonic() - start_time:.1f}s")


def cmd_gen(args):
    repo = find_repo()
    target = Target(args.target)
    name = args.name or target.host.split(".")[0].replace("-", "_").replace(":", "_")
    if not name.isidentifier():
        fail(f"{name!r} is not usable as a nix attribute name, pass --name")

    with console.status(f"probing {target.raw}"):
        p = parse_probe(target.run(PROBE_SH))
    show_probe(p)

    if not p.get("v4") and not p.get("v6"):
        fail("could not determine any usable address")

    disk = args.disk or p.get("root_disk") or (p["disks"][0][0] if p["disks"] else "/dev/vda")
    host_dir = repo / "modules/hosts" / name
    host_file, disko_file = host_dir / "default.nix", host_dir / "disko.nix"

    if host_file.exists() and not args.force:
        console.print(f"[yellow]host {name} already exists at {host_dir.relative_to(repo)}[/] (use --force to overwrite)")
        return

    host_dir.mkdir(parents=True, exist_ok=True)
    def_content, disko_content = render_host(name, p, disk)
    host_file.write_text(def_content)
    disko_file.write_text(disko_content)
    subprocess.run(["git", "add", "-N", str(host_file), str(disko_file)], cwd=repo, check=False)

    console.print(f"[bold green]generated configuration:[/] {host_file.relative_to(repo)} & {disko_file.relative_to(repo)}")
    console.print(f"next: [bold]induo write {target.raw} --name {name}[/]")


def cmd_write(args):
    repo = find_repo()
    target = Target(args.target)
    name = args.name or target.host.split(".")[0].replace("-", "_").replace(":", "_")
    if not name.isidentifier():
        fail(f"{name!r} is not usable as a nix attribute name, pass --name")

    if stage_port := target.is_stage():
        console.print(f"[green]target is in RAM stage[/] (port {stage_port})")
        disk = args.disk
        if not disk:
            fail("target is in RAM stage, specify target disk via --disk (e.g. --disk /dev/vda)")
        image, _, is_compressed = build_image(repo, name)
        stage_target = Target(f"root@{target.host}", port=stage_port)
        write_disk(stage_target, image, disk, is_compressed=is_compressed)
        stage_target.detach("sync; reboot -f")
        if wait_port(target.host, 22, 600, "NixOS"):
            console.print(f"[bold green]{name} is up:[/] ssh root@{target.host}")
        return

    with console.status(f"probing {target.raw}"):
        p = parse_probe(target.run(PROBE_SH))

    if not p.get("v4") and not p.get("v6"):
        fail("could not determine any usable address")

    disk = args.disk or p.get("root_disk") or (p["disks"][0][0] if p["disks"] else "/dev/vda")
    keys = resolve_keys(repo, name, args.key)
    image, size, is_compressed = build_image(repo, name)

    console.print(f"deploying [bold]{name}[/] ({size / (1024 ** 3):.1f} GiB) -> {target.raw} on [bold]{disk}[/]")
    deploy_and_boot_stage(target, p, make_stage_initrd(keys, p), args.timeout)

    stage_port = 0
    deadline = time.monotonic() + 300
    with console.status(f"waiting for RAM stage on {target.host}"):
        while time.monotonic() < deadline:
            if stage_port := target.is_stage():
                break
            time.sleep(3)

    if not stage_port:
        fail("stage never came up; watchdog will reboot into old system")

    console.print(f"stage is up: [dim]ssh -p {stage_port} root@{target.host}[/]")
    stage_target = Target(f"root@{target.host}", port=stage_port)
    write_disk(stage_target, image, disk, is_compressed=is_compressed)
    stage_target.detach("sync; reboot -f")
    if wait_port(target.host, 22, 600, "NixOS"):
        console.print(f"[bold green]{name} is up:[/] ssh root@{target.host}")
    else:
        console.print("[yellow]no ssh yet[/]; check provider console")


def main():
    ap = argparse.ArgumentParser(prog="induo", description="Deploy NixOS flake configuration to remote host in RAM")
    sub = ap.add_subparsers(dest="command", required=True)

    p_gen = sub.add_parser("gen", help="Probe remote host and generate NixOS + Disko configuration")
    p_gen.add_argument("target", help="SSH target (e.g. root@host or user@host)")
    p_gen.add_argument("--name", help="Flake host attribute name")
    p_gen.add_argument("--disk", help="Target disk")
    p_gen.add_argument("--force", "-f", action="store_true", help="Overwrite existing host configuration files")

    p_write = sub.add_parser("write", help="Build and write NixOS image to remote host in RAM")
    p_write.add_argument("target", help="SSH target (e.g. root@host or user@host)")
    p_write.add_argument("--name", help="Flake host attribute name")
    p_write.add_argument("--disk", help="Target disk to overwrite")
    p_write.add_argument("--key", action="append", help="Public key file for Stage SSH")
    p_write.add_argument("--timeout", type=int, default=180, help="Stage watchdog timeout in seconds")

    args = ap.parse_args()
    (cmd_gen if args.command == "gen" else cmd_write)(args)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        console.print()
