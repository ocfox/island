#!/bin/sh
set -eu

config_file="@configPath@"
target="${1:-}"

get_config() {
  @jq@/bin/jq -r "$1" "$config_file"
}

efi_mount="$(get_config ".efiMountPoint // \"/boot\"")"
limine_pkg="$(get_config ".liminePath")"
limine_bin="$limine_pkg/bin/limine"
efi_support="$(get_config ".efiSupport")"
efi_removable="$(get_config ".efiRemovable")"
bios_support="$(get_config ".biosSupport")"
bios_device="$(get_config ".biosDevice // \"nodev\"")"
timeout="$(get_config ".timeout")"
[ "$timeout" = "no" ] && timeout=0
max_gens="$(get_config ".maxGenerations")"
[ "$max_gens" = "0" ] || [ "$max_gens" = "null" ] && max_gens=5
extra_config="$(get_config ".extraConfig // \"\"")"
extra_entries="$(get_config ".extraEntries // \"\"")"
arch_family="$(get_config ".hostArchitecture.family // \"x86\"")"
arch_bits="$(get_config ".hostArchitecture.bits // 64")"
distro_name="$(get_config ".distroName // \"NixOS\"")"

limine_dir="$efi_mount/limine"
kernel_dir="$limine_dir/kernels"
mkdir -p "$limine_dir" "$kernel_dir"

# 1. Install Limine EFI / BIOS binaries
if [ "$efi_support" = "true" ]; then
  if [ "$arch_family" = "arm" ]; then
    efi_bin="BOOTAA64.EFI"
  else
    efi_bin="BOOTX64.EFI"
  fi

  src_efi="$limine_pkg/share/limine/$efi_bin"
  if [ "$efi_removable" = "true" ]; then
    dst_efi="$efi_mount/EFI/BOOT/$efi_bin"
  else
    dst_efi="$efi_mount/EFI/limine/$efi_bin"
  fi
  mkdir -p "$(dirname "$dst_efi")"
  cp -f "$src_efi" "$dst_efi"
fi

if [ "$bios_support" = "true" ] || [ "$bios_device" != "nodev" ]; then
  cp -f "$limine_pkg/share/limine/limine-bios.sys" "$efi_mount/limine-bios.sys"
  if [ "$bios_device" != "nodev" ] && [ -b "$bios_device" ]; then
    part_idx="$(get_config ".partitionIndex // \"\"")"
    if [ -n "$part_idx" ] && [ "$part_idx" != "null" ]; then
      "$limine_bin" bios-install "$bios_device" "$part_idx" 2>/dev/null || true
    else
      "$limine_bin" bios-install "$bios_device" 2>/dev/null || true
    fi
  else
    for dev in /dev/vda /dev/sda /dev/nvme0n1; do
      if [ -b "$dev" ]; then
        "$limine_bin" bios-install "$dev" 1 2>/dev/null || true
        break
      fi
    done
  fi
fi

# Copy additional files if configured
@jq@/bin/jq -r ".additionalFiles | to_entries[] | \"\(.key)\t\(.value)\"" "$config_file" 2>/dev/null | while IFS="$(printf "\t")" read -r dst src; do
  [ -z "$dst" ] && continue
  mkdir -p "$(dirname "$efi_mount/$dst")"
  cp -f "$src" "$efi_mount/$dst"
done

# 2. Generate limine.conf
conf_tmp="$limine_dir/limine.conf.tmp"
cat << EOF > "$conf_tmp"
timeout: $timeout
editor_enabled: no
graphics: yes
default_entry: 2
$extra_config
EOF

active_files_tmp="$(mktemp)"

add_entry() {
  num="$1"
  path="$2"
  label="$3"

  [ -e "$path" ] || return 0

  k_src="$(readlink -f "$path/kernel" 2>/dev/null || true)"
  i_src="$(readlink -f "$path/initrd" 2>/dev/null || true)"
  [ -n "$k_src" ] && [ -f "$k_src" ] || return 0

  k_name="$(basename "$k_src")"
  i_name=""
  [ -n "$i_src" ] && [ -f "$i_src" ] && i_name="$(basename "$i_src")"

  k_dst="k-$k_name"
  i_dst=""
  [ -n "$i_name" ] && i_dst="i-$i_name"

  [ -f "$kernel_dir/$k_dst" ] || cp -f "$k_src" "$kernel_dir/$k_dst"
  echo "$k_dst" >> "$active_files_tmp"

  if [ -n "$i_dst" ]; then
    [ -f "$kernel_dir/$i_dst" ] || cp -f "$i_src" "$kernel_dir/$i_dst"
    echo "$i_dst" >> "$active_files_tmp"
  fi

  params=""
  [ -f "$path/kernel-params" ] && params="$(cat "$path/kernel-params")"
  init_path="$path/init"

  cat << ENTRY >> "$conf_tmp"
/$distro_name - Generation $num$label
    protocol: linux
    kernel_path: boot():/limine/kernels/$k_dst
    cmdline: init=$init_path $params
ENTRY

  if [ -n "$i_dst" ]; then
    echo "    module_path: boot():/limine/kernels/$i_dst" >> "$conf_tmp"
  fi
}

# Add default/target system first
if [ -n "$target" ] && [ -e "$target" ]; then
  add_entry "current" "$target" " (Default)"
fi

# Add historical generations
if [ -d "/nix/var/nix/profiles" ]; then
  for link in $(find /nix/var/nix/profiles/ -maxdepth 1 -name "system-*-link" 2>/dev/null | sort -V -r | head -n "$max_gens"); do
    [ -e "$link" ] || continue
    g_num=$(basename "$link" | sed -E "s/system-([0-9]+)-link/\\1/")
    g_target=$(readlink -f "$link")
    [ "$g_target" = "$target" ] && continue
    add_entry "$g_num" "$link" ""
  done
fi

# Append extra custom entries
if [ -n "$extra_entries" ]; then
  echo "" >> "$conf_tmp"
  echo "$extra_entries" >> "$conf_tmp"
fi

mv -f "$conf_tmp" "$limine_dir/limine.conf"

# 3. Clean up unreferenced kernel and initrd files
for f in "$kernel_dir"/k-* "$kernel_dir"/i-*; do
  [ -e "$f" ] || continue
  fname="$(basename "$f")"
  grep -qx "$fname" "$active_files_tmp" || rm -f "$f"
done
rm -f "$active_files_tmp"

sync
