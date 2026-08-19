#!/usr/bin/env python3
"""induo: deploy a NixOS flake configuration to any remote Linux machine in RAM."""

import argparse
import io
import json
import os
import socket
import subprocess
import time
from pathlib import Path
from rich.console import Console
from rich.table import Table

console = Console(highlight=False)
err = Console(stderr=True, highlight=False)

STAGE = os.environ.get("INDUO_STAGE", "@stage@")
REMOTE_DIR = "/var/tmp/induo"
STAGE_PORT = 2222
STATE_VERSION = "25.11"

SSH_BASE = [
    "-o", "ConnectTimeout=10",
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
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


def ssh_argv(target: str, port: int = 22, tool: str = "ssh") -> list[str]:
    if tool == "scp":
        return ["scp"] + SSH_BASE + (["-P", str(port)] if port != 22 else [])
    return ["ssh"] + SSH_BASE + (["-p", str(port)] if port != 22 else [])


def ssh(target: str, command: str, port: int = 22, check: bool = True) -> str:
    host = target.split("@")[-1].strip("[]")
    user = target.split("@")[0] if "@" in target else None
    dest = f"{user}@{host}" if user else host
    argv = ssh_argv(target, port) + [dest, command]
    proc = subprocess.run(argv, capture_output=True, text=True)
    if check and proc.returncode != 0:
        err_text = proc.stderr.strip() or proc.stdout.strip() or f"exit code {proc.returncode}"
        fail(f"ssh {target}: {err_text}")
    return proc.stdout


def ssh_pipe(target: str, data: bytes | Path, remote_file: str, port: int = 22):
    """Stream binary data or a local file directly into a remote file via SSH stdin."""
    host = target.split("@")[-1].strip("[]")
    user = target.split("@")[0] if "@" in target else None
    dest = f"{user}@{host}" if user else host
    argv = ssh_argv(target, port) + [dest, f"cat > '{remote_file}'"]
    if isinstance(data, (str, Path)):
        with open(data, "rb") as f:
            proc = subprocess.run(argv, stdin=f, capture_output=True)
    else:
        proc = subprocess.run(argv, input=data, capture_output=True)
    if proc.returncode != 0:
        fail(f"pipe to {remote_file}: {proc.stderr.decode().strip()}")


def ssh_detach(target: str, command: str, port: int = 22):
    """Run a background command that safely survives disconnection."""
    host = target.split("@")[-1].strip("[]")
    user = target.split("@")[0] if "@" in target else None
    dest = f"{user}@{host}" if user else host
    quoted = "'" + command.replace("'", "'\\''") + "'"
    argv = ssh_argv(target, port) + [dest, f"nohup sh -c {quoted} </dev/null >/dev/null 2>&1 &"]
    subprocess.run(argv, capture_output=True, text=True)


def check_ssh_banner(host: str, port: int, timeout: float = 3.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout) as s:
            s.settimeout(timeout)
            banner = s.recv(1024)
            return banner.startswith(b"SSH-")
    except OSError:
        return False


def wait_port(host: str, port: int, timeout: int, what: str) -> bool:
    deadline = time.monotonic() + timeout
    with console.status("") as status:
        while time.monotonic() < deadline:
            if check_ssh_banner(host, port, timeout=2.0):
                return True
            left = int(deadline - time.monotonic())
            status.update(f"waiting for {what} on {host}:{port} [dim]({left}s left)[/]")
            time.sleep(3)
    return False


def wait_stage(stage_target: str, timeout: int) -> int:
    host = stage_target.split("@")[-1].strip("[]")
    deadline = time.monotonic() + timeout
    with console.status("") as status:
        while time.monotonic() < deadline:
            for port in (22, 2222):
                if check_ssh_banner(host, port, timeout=1.5):
                    argv = ssh_argv(stage_target, port) + [stage_target, "test -f /run/induo-stage"]
                    if subprocess.run(argv, capture_output=True).returncode == 0:
                        return port
            left = int(deadline - time.monotonic())
            status.update(f"waiting for RAM stage on {host} [dim]({left}s left)[/]")
            time.sleep(3)
    return 0


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
  name=$(basename "$d")
  case "$name" in loop*|ram*|zram*|sr*|dm-*) continue ;; esac
  size=$(cat "$d/size" 2>/dev/null || echo 0)
  [ "$size" -gt 0 ] && echo "/dev/$name $((size * 512))"
done
"""


def load_json(raw: str):
    return json.loads(raw) if raw.strip() else []


def token_after(s: str, marker: str) -> str:
    tokens = s.split()
    if marker in tokens:
        i = tokens.index(marker)
        if i + 1 < len(tokens):
            return tokens[i + 1]
    return ""


def default_gateway(routes: list, dev: str) -> str:
    for r in routes:
        if r.get("dst") == "default" and r.get("dev") == dev:
            return r.get("gateway", "")
    return ""


def pick_address(addrs: list, dev: str, family: str, preferred: str = "") -> tuple[str, bool]:
    for entry in addrs:
        if entry.get("ifname") != dev:
            continue
        for info in entry.get("addr_info", []):
            if info.get("family") != family:
                continue
            if info.get("scope") == "link":
                continue
            ip = info.get("local", "")
            prefix = info.get("prefixlen", 32 if family == "inet" else 128)
            dynamic = bool(info.get("dynamic"))
            if preferred and ip == preferred:
                return f"{ip}/{prefix}", dynamic
            if not preferred and ip:
                return f"{ip}/{prefix}", dynamic
    return "", False


def parse_probe(raw: str) -> dict:
    sections = {}
    current = None
    for line in raw.splitlines():
        if line.startswith("@@"):
            current = line[2:]
            sections[current] = []
        elif current:
            sections[current].append(line)
    s = {k: "\n".join(v).strip() for k, v in sections.items()}

    links = load_json(s.get("link", ""))
    addrs = load_json(s.get("addr", ""))
    result = {
        "firmware": s.get("firmware", "bios"),
        "arch": s.get("arch", "x86_64"),
        "memory_kib": int(s.get("mem", "0") or 0),
        "disks": [(line.split()[0], int(line.split()[1])) for line in s.get("disks", "").splitlines() if line],
        "root_disk": "",
    }

    rootsrc = s.get("rootsrc", "")
    for dev, _ in result["disks"]:
        if rootsrc.startswith(dev):
            result["root_disk"] = dev
            break

    for version, family, get_key, route_key in ((4, "inet", "get4", "route4"), (6, "inet6", "get6", "route6")):
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


def show_probe(p: dict):
    tbl = Table.grid(padding=(0, 2))
    tbl.add_column(style="dim")
    tbl.add_column()
    tbl.add_row("firmware", p["firmware"])
    tbl.add_row("arch", p["arch"])
    tbl.add_row("memory", f"{p['memory_kib'] // 1024} MiB")
    for v in (4, 6):
        if s := p.get(f"v{v}"):
            dyn = " (dhcp/ra)" if s["dynamic"] else " (static)"
            tbl.add_row(f"IPv{v}", f"{s['address']} via {s['gateway']} on {s['dev']}{dyn}")
    for d, sz in p["disks"]:
        mark = " [bold green]<- current root[/]" if d == p["root_disk"] else ""
        tbl.add_row("disk", f"{d} {sz / (1024 ** 3):.1f} GiB{mark}")
    console.print(tbl)


def render_host(name: str, p: dict) -> str:
    target_disk = p.get("root_disk") or (p["disks"][0][0] if p.get("disks") else "/dev/vda")
    pin_addrs = []
    routes = []
    dhcp = "yes"

    static = [v for v in ("v4", "v6") if p.get(v) and not p[v]["dynamic"]]
    if static:
        dhcp = {("v4",): "ipv6", ("v6",): "ipv4"}.get(tuple(static), "no")
        for v in static:
            pin_addrs.append(p[v]["address"])
            routes.append(f'          {{ Gateway = "{p[v]["gateway"]}"; }}')

    # AWS stateful DHCPv6 assigns /128 to ENI; systemd-networkd needs it pinned explicitly
    if p.get("v6") and p["v6"]["address"].endswith("/128"):
        if p["v6"]["address"] not in pin_addrs:
            pin_addrs.append(p["v6"]["address"])

    net_block = []
    if pin_addrs or routes or dhcp != "yes":
        net_block += ['        systemd.network.networks."10-eth0" = {']
        if dhcp != "yes":
            net_block.append(f'          networkConfig.DHCP = "{dhcp}";')
        if pin_addrs:
            addrs_str = " ".join(f'"{a}"' for a in pin_addrs)
            net_block.append(f"          address = [ {addrs_str} ];")
        if routes:
            net_block += ["          routes = [", *routes, "          ];"]
        net_block += ["        };"]

    net_body = ("\n" + "\n".join(net_block)) if net_block else ""
    return f"""{{ self, ... }}:
{{
  hosts.{name} = {{
    system = "{p['arch']}-linux";
    stateVersion = "{STATE_VERSION}";
    module =
      {{ ... }}:
      {{
        imports = with self.modules.nixos; [
          vps
        ];

        boot.growPartition = true;

        boot.loader.grub.enable = false;
        boot.loader.efi.canTouchEfiVariables = false;
        boot.loader.limine = {{
          enable = true;
          efiSupport = true;
          efiInstallAsRemovable = true;
          biosSupport = true;
          biosDevice = "{target_disk}";
          partitionIndex = 2;
        }};

        fileSystems."/" = {{
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
          autoResize = true;
        }};

        fileSystems."/boot" = {{
          device = "/dev/disk/by-label/ESP";
          fsType = "vfat";
          options = [
            "fmask=0077"
            "dmask=0077"
          ];
        }};{net_body}
      }};
  }};
}}
"""


def eval_host_keys(repo: Path, name: str) -> list[str]:
    expr = f""".#nixosConfigurations.{name}.config"""
    apply = r"c: (c.users.users.${c.my.name}.openssh.authorizedKeys.keys or []) ++ (c.users.users.root.openssh.authorizedKeys.keys or [])"
    argv = ["nix", "eval", expr, "--apply", apply, "--json"]
    proc = subprocess.run(argv, cwd=repo, capture_output=True, text=True)
    if proc.returncode == 0:
        try:
            return json.loads(proc.stdout)
        except Exception:
            pass
    return []


def resolve_keys(repo: Path, name: str, explicit_keys: list[str] | None) -> list[str]:
    if explicit_keys:
        return [Path(k).read_text().strip() for k in explicit_keys]
    keys = eval_host_keys(repo, name)
    if keys:
        return keys
    local_pubs = list(Path.home().glob(".ssh/*.pub"))
    if local_pubs:
        return [p.read_text().strip() for p in local_pubs]
    fail("no authorized keys found in nixos config or ~/.ssh/*.pub")


def build_image(repo: Path, name: str) -> tuple[Path, int]:
    attr = f".#nixosConfigurations.{name}.config.system.build.diskImage"
    console.print(f"[dim]building {attr}[/]")
    argv = ["nix", "build", attr, "--no-link", "--print-out-paths"]
    proc = subprocess.run(argv, cwd=repo, capture_output=True, text=True)
    if proc.returncode != 0:
        fail(f"nix build failed: {proc.stderr}")
    out = Path(proc.stdout.strip())
    size = int((out / "size").read_text().strip())
    return out / "nixos.img.zst", size


def cpio_entry(name: str, body: bytes, mode: int) -> bytes:
    """Format a single newc (SVR4 no-CRC) cpio archive entry."""
    name_b = name.encode("ascii") + b"\0"
    header = (
        f"070701"
        f"{0:08x}"
        f"{mode:08x}"
        f"{0:08x}"
        f"{0:08x}"
        f"{1:08x}"
        f"{int(time.time()):08x}"
        f"{len(body):08x}"
        f"{0:08x}{0:08x}{0:08x}{0:08x}"
        f"{len(name_b):08x}"
        f"{0:08x}"
    ).encode("ascii")
    header_pad = b"\0" * ((4 - (len(header) + len(name_b)) % 4) % 4)
    body_pad = b"\0" * ((4 - len(body) % 4) % 4)
    return header + name_b + header_pad + body + body_pad


def cpio_trailer() -> bytes:
    return cpio_entry("TRAILER!!!", b"", 0)


def make_stage_initrd(keys: list[str], p: dict) -> bytes:
    """Prepend an uncompressed cpio containing /induo/net.sh and SSH keys to STAGE/initrd."""
    net_sh_lines = [
        "#!/bin/sh",
        "",
        "wait_dev() {",
        "  mac=$1",
        '  if [ -n "$mac" ]; then',
        "    for i in $(seq 1 10); do",
        "      for d in /sys/class/net/*; do",
        '        [ -r "$d/address" ] && [ "$(cat "$d/address" 2>/dev/null)" = "$mac" ] && basename "$d" && return 0',
        "      done",
        "      sleep 1",
        "    done",
        "  fi",
        "  for d in /sys/class/net/*; do",
        '    name=$(basename "$d")',
        '    [ "$name" != "lo" ] && echo "$name" && return 0',
        "  done",
        '  echo "eth0"',
        "  return 0",
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
            net_sh_lines += [
                f'{var}=$(wait_dev "{stack["mac"]}")',
                f'echo "induo: configuring {var}=${{{var}}}"',
                f'ip link set "${var}" up 2>/dev/null || true',
                f'udhcpc -i "${var}" -b -s /etc/udhcpc.script 2>/dev/null || true',
                "\tsleep 1",
            ]
        ip_cmd = "ip -6" if version == 6 else "ip"
        ping_cmd = f'ping -6 -c 2 -W 1 -I "${var}" {stack["gateway"]} >/dev/null 2>&1 || true' if version == 6 else f'ping -c 2 -W 1 {stack["gateway"]} >/dev/null 2>&1 || true'
        net_sh_lines += [
            f'echo "induo: assigning {stack["address"]} to ${{{var}}}"',
            f'{ip_cmd} addr add {stack["address"]} dev "${var}" || true',
            f'{ip_cmd} route add {stack["gateway"]} dev "${var}" 2>/dev/null || true',
            f'{ip_cmd} route add default via {stack["gateway"]} dev "${var}" onlink 2>/dev/null || true',
            f"{ping_cmd}",
            "",
        ]

    net_sh = "\n".join(net_sh_lines)
    auth_keys = "\n".join(keys) + "\n"

    buf = io.BytesIO()
    buf.write(cpio_entry("induo", b"", 0o040755))
    buf.write(cpio_entry("induo/net.sh", net_sh.encode(), 0o100755))
    buf.write(cpio_entry("root", b"", 0o040700))
    buf.write(cpio_entry("root/.ssh", b"", 0o040700))
    buf.write(cpio_entry("root/.ssh/authorized_keys", auth_keys.encode(), 0o100600))
    buf.write(cpio_trailer())

    with open(f"{STAGE}/initrd", "rb") as f:
        buf.write(f.read())
    return buf.getvalue()


def deploy_and_boot_stage(target: str, p: dict, initrd: bytes, timeout: int):
    k_path = Path(f"{STAGE}/kernel")
    g_path = Path(f"{STAGE}/grub.efi")
    k_sz = k_path.stat().st_size
    initrd_sz = len(initrd)
    g_sz = g_path.stat().st_size if g_path.exists() else 0
    total_sz = k_sz + initrd_sz + g_sz

    console.print(f"stage [bold]{total_sz / (1024 * 1024):.1f} MiB[/] (kernel {k_sz / (1024 * 1024):.1f}M, initrd {initrd_sz / (1024 * 1024):.1f}M, grub {g_sz / (1024 * 1024):.1f}M) -> {target}:{REMOTE_DIR}")
    with console.status(f"uploading stage ({total_sz / (1024 * 1024):.1f} MiB) to {target}:{REMOTE_DIR}"):
        ssh(target, f"sudo rm -rf {REMOTE_DIR} && sudo mkdir -p {REMOTE_DIR} && sudo chown -R $USER:$USER {REMOTE_DIR}")
        ssh_pipe(target, k_path, f"{REMOTE_DIR}/kernel")
        ssh_pipe(target, initrd, f"{REMOTE_DIR}/initrd")
        if g_path.exists():
            ssh_pipe(target, g_path, f"{REMOTE_DIR}/grub.efi")

    cmdline = f"console=tty0 console=ttyS0,115200 panic=10 net.ifnames=0 induo.timeout={timeout}"
    boot_sh = f"""
set -e

# Copy kernel & initrd to both /boot/induo and /induo
sudo mkdir -p /boot/induo /induo
sudo cp -f {REMOTE_DIR}/kernel /boot/induo/kernel
sudo cp -f {REMOTE_DIR}/initrd /boot/induo/initrd
sudo cp -f {REMOTE_DIR}/kernel /induo/kernel 2>/dev/null || true
sudo cp -f {REMOTE_DIR}/initrd /induo/initrd 2>/dev/null || true
sudo chmod -R 755 /boot/induo /induo 2>/dev/null || true

# 1. Direct UEFI BootNext via standalone grub.efi
if [ -d /sys/firmware/efi ]; then
  for d in /boot/efi /boot/EFI /efi /boot; do
    if [ -d "$d/EFI" ] || mount | grep -q "on $d type vfat"; then
      efi_dir="$d"
      break
    fi
  done
  if [ -n "$efi_dir" ]; then
    dev_part=$(findmnt -n -o SOURCE "$efi_dir" 2>/dev/null || df "$efi_dir" | awk 'NR==2{{print $1}}')
    if [ -b "$dev_part" ]; then
      disk=$(echo "$dev_part" | sed -E 's/p?[0-9]+$//')
      part=$(echo "$dev_part" | grep -o '[0-9]*$')
      sudo mkdir -p "$efi_dir/EFI/induo"
      sudo cp -f {REMOTE_DIR}/grub.efi "$efi_dir/EFI/induo/grub.efi"
      sudo chmod -R 755 "$efi_dir/EFI/induo" 2>/dev/null || true

      for num in $(sudo efibootmgr 2>/dev/null | grep "induo" | awk '{{print $1}}' | sed -e 's/Boot//' -e 's/\\*//'); do
        sudo efibootmgr -B -b "$num" >/dev/null 2>&1 || true
      done

      if sudo efibootmgr -c -d "$disk" -p "$part" -L "induo" -l "\\EFI\\induo\\grub.efi" >/dev/null 2>&1; then
        boot_num=$(sudo efibootmgr 2>/dev/null | grep "induo" | awk '{{print $1}}' | sed -e 's/Boot//' -e 's/\\*//' | head -1)
        if [ -n "$boot_num" ] && sudo efibootmgr -n "$boot_num" >/dev/null 2>&1; then
          echo "BOOT_EFI"
          exit 0
        fi
      fi
    fi
  fi
fi

# 2. Legacy BIOS / custom.cfg
grub_entry='set timeout=3\\nmenuentry "induo-stage" --unrestricted {{\\n    insmod all_video\\n    insmod gzio\\n    insmod part_gpt\\n    insmod part_msdos\\n    insmod ext2\\n    insmod xfs\\n    search --no-floppy --file --set=root /induo/kernel\\n    if [ -f ($root)/boot/induo/kernel ]; then\\n      linux /boot/induo/kernel {cmdline}\\n      initrd /boot/induo/initrd\\n    else\\n      linux /induo/kernel {cmdline}\\n      initrd /induo/initrd\\n    fi\\n}}\\n'
for cfg in /boot/grub2/custom.cfg /boot/grub/custom.cfg /etc/grub.d/40_custom; do
  if [ -d "$(dirname "$cfg")" ]; then
    printf "$grub_entry" | sudo tee "$cfg" >/dev/null 2>&1 || true
  fi
done
sudo grub2-reboot "induo-stage" 2>/dev/null || sudo grub-reboot "induo-stage" 2>/dev/null || sudo grub2-set-default "induo-stage" 2>/dev/null || true
echo "BOOT_GRUB"
"""
    boot_mode = ssh(target, boot_sh).strip().splitlines()[-1]
    console.print(f"[dim]rebooting via {boot_mode.lower()}...[/]")
    ssh_detach(target, "sudo reboot || reboot")


def write_disk(stage_target: str, image: Path, disk: str, size: int, port: int = 22):
    host = stage_target.split("@")[-1].strip("[]")
    img_size = image.stat().st_size
    console.print(f"writing [bold]{image.name}[/] ({img_size / (1024 * 1024):.1f} MiB) -> [bold]{disk}[/]")

    # 1. Ensure sd_mod is loaded and block device exists
    fix_disk_cmd = f"modprobe sd_mod 2>/dev/null || true; mdev -s 2>/dev/null || true; [ -b {disk} ] || (rm -f {disk}; mknod {disk} b 8 0 2>/dev/null || true)"
    ssh(stage_target, fix_disk_cmd, port=port)

    # 2. High-speed dual-stack raw TCP socket streaming (15~100+ MB/s)
    receiver_cmd = f"killall -9 nc 2>/dev/null || true; touch /run/active && (busybox nc -l -p 8888 -s :: </dev/null || busybox nc -l -p 8888 </dev/null) | zstd -dc | dd of={disk} bs=4M conv=fsync"
    ssh_detach(stage_target, receiver_cmd, port=port)

    sock = None
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        try:
            sock = socket.create_connection((host, 8888), timeout=2)
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            sock.settimeout(300)
            break
        except (ConnectionRefusedError, OSError):
            time.sleep(0.3)

    if sock is not None:
        start_time = time.monotonic()
        sent = 0
        with sock, image.open("rb") as f, console.status("") as status:
            while chunk := f.read(1024 * 1024):
                try:
                    sock.sendall(chunk)
                except (BrokenPipeError, ConnectionResetError, OSError) as e:
                    if sent >= img_size * 0.98:
                        break
                    fail(f"direct TCP transfer failed after {sent / (1024 * 1024):.1f} MiB: {e}")
                sent += len(chunk)
                elapsed = max(0.1, time.monotonic() - start_time)
                speed = sent / elapsed
                pct = min(100.0, (sent / img_size) * 100)
                status.update(f"streaming image {sent / (1024 * 1024):.1f}/{img_size / (1024 * 1024):.1f} MiB [bold cyan]({pct:.1f}%)[/] @ [bold green]{speed / (1024 * 1024):.1f} MB/s[/]")
            try:
                sock.shutdown(socket.SHUT_WR)
            except OSError:
                pass
        console.print(f"[bold green]disk write complete:[/] {disk} in {time.monotonic() - start_time:.1f}s")
        return

    console.print("[yellow]direct TCP connection failed, falling back to SSH pipe...[/]")
    cmd_fallback = f"touch /run/active && zstd -dc | dd of={disk} bs=4M conv=fsync"
    argv = [
        "ssh",
        *SSH_BASE,
        *(["-p", str(port)] if port != 22 else []),
        "-o", "Compression=no",
        "-o", "IPQoS=throughput",
        stage_target,
        cmd_fallback,
    ]
    with image.open("rb") as f:
        proc = subprocess.run(argv, stdin=f)
        if proc.returncode != 0:
            fail("write failed; stage remains alive for rescue")


def main():
    ap = argparse.ArgumentParser(description="Deploy NixOS disk image to remote host in RAM")
    ap.add_argument("target", help="SSH target (e.g. user@host)")
    ap.add_argument("--name", help="NixOS configuration name (default: derived from hostname)")
    ap.add_argument("--disk", help="Target disk to overwrite (e.g. /dev/nvme0n1)")
    ap.add_argument("--write", action="store_true", help="Actually overwrite the remote disk")
    ap.add_argument("--regen", action="store_true", help="Regenerate host nix file if exists")
    ap.add_argument("--key", action="append", help="Public key file for Stage SSH")
    ap.add_argument("--timeout", type=int, default=1800, help="Stage watchdog timeout in seconds")
    args = ap.parse_args()

    repo = find_repo()
    target = args.target
    host = target.split("@")[-1].strip("[]")
    stage_target = f"root@{host}"
    name = args.name or host.split(".")[0].replace("-", "_").replace(":", "_")
    if not name.isidentifier():
        fail(f"{name!r} is not usable as a nix attribute name, pass --name")

    # If already in RAM stage, jump directly to writing
    for p_test in (22, 2222):
        if check_ssh_banner(host, p_test, timeout=1.5):
            argv = ssh_argv(stage_target, p_test) + [stage_target, "test -f /run/induo-stage"]
            if subprocess.run(argv, capture_output=True).returncode == 0:
                console.print(f"[green]target is in RAM stage[/] (ssh -p {p_test} {stage_target})")
                if not args.disk:
                    fail("target is in RAM stage, specify --disk to proceed (e.g. --disk /dev/nvme0n1 --write)")
                if not args.write:
                    console.print(f"to write: [bold]induo {target} --name {name} --disk {args.disk} --write[/]")
                    return
                image, size = build_image(repo, name)
                write_disk(stage_target, image, args.disk, size, port=p_test)
                ssh_detach(stage_target, "sync; reboot -f", port=p_test)
                if wait_port(host, 22, 600, "NixOS"):
                    console.print(f"[bold green]{name} is up:[/] ssh {stage_target}")
                return

    with console.status(f"probing {target}"):
        p = parse_probe(ssh(target, PROBE_SCRIPT))
    show_probe(p)

    if not p.get("v4") and not p.get("v6"):
        fail("could not determine any usable address")

    if not args.disk:
        hint = p["root_disk"] or (p["disks"][0][0] if p["disks"] else "/dev/vda")
        console.print(f"\nnothing was touched. to continue: [bold]induo {target} --disk {hint}[/]")
        return
    if not any(args.disk == d for d, _ in p["disks"]):
        fail(f"{args.disk} is not one of the disks reported by {target}")

    # Generate or verify modules/hosts/<name>/default.nix
    host_file = repo / "modules/hosts" / name / "default.nix"
    if args.regen or not host_file.exists():
        host_file.parent.mkdir(parents=True, exist_ok=True)
        host_file.write_text(render_host(name, p))
        subprocess.run(["git", "add", "-N", str(host_file)], cwd=repo)
        console.print(f"wrote [bold]{host_file.relative_to(repo)}[/]")
    else:
        subprocess.run(["git", "add", "-N", str(host_file)], cwd=repo)
        console.print(f"keeping [bold]{host_file.relative_to(repo)}[/] [dim](--regen to rewrite)[/]")

    keys = resolve_keys(repo, name, args.key)
    image, size = build_image(repo, name)
    disk_size = next(sz for d, sz in p["disks"] if d == args.disk)
    if disk_size < size:
        fail(f"{args.disk} ({disk_size / (1024 ** 3):.1f} GiB) is smaller than image ({size / (1024 ** 3):.1f} GiB)")
    console.print(f"image {size / (1024 ** 3):.1f} GiB -> {args.disk} {disk_size / (1024 ** 3):.1f} GiB")

    initrd = make_stage_initrd(keys, p)
    deploy_and_boot_stage(target, p, initrd, args.timeout)

    stage_port = wait_stage(stage_target, 300)
    if not stage_port:
        fail("stage never came up; watchdog will reboot into old system")
    console.print(f"stage is up: [dim]ssh -p {stage_port} {stage_target}[/]")

    if not args.write:
        console.print(f"\ndisk untouched. add [bold]--write[/] to overwrite {args.disk}")
        return

    write_disk(stage_target, image, args.disk, size, port=stage_port)
    ssh_detach(stage_target, "sync; reboot -f", port=stage_port)
    if wait_port(host, 22, 600, "NixOS"):
        console.print(f"[bold green]{name} is up:[/] ssh {stage_target}")
    else:
        console.print("[yellow]no ssh yet[/]; check provider console")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        console.print()
