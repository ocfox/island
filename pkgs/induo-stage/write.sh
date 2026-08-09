#!/bin/sh
# ssh -p 2222 root@host induo-write /dev/vda 2147483648 < image.zst
#
# The target is re-validated here rather than trusted from the client: by this
# point the original system is gone, so this is the last chance to catch a
# wrong or undersized device.
set -eu

dev="${1:?usage: induo-write <device> <uncompressed-bytes>}"
need="${2:?usage: induo-write <device> <uncompressed-bytes>}"
name="${dev#/dev/}"

if [ ! -b "$dev" ] || [ ! -r "/sys/block/$name/size" ]; then
	echo "induo-write: $dev is not a whole disk on this machine" >&2
	echo "available:" >&2
	for d in /sys/block/*; do
		s=$(cat "$d/size" 2>/dev/null || echo 0)
		[ "$s" -gt 0 ] && echo "  /dev/$(basename "$d") $((s * 512))" >&2
	done
	exit 1
fi

# sysfs size is in 512-byte units regardless of the logical block size
have=$(($(cat "/sys/block/$name/size") * 512))
if [ "$have" -lt "$need" ]; then
	echo "induo-write: $dev is $have bytes, image needs $need" >&2
	exit 1
fi

echo "induo-write: writing $dev ($have bytes available, image is $need)" >&2

mkdir -p /run/induo
: >/run/induo/active

zstd -dc | dd of="$dev" bs=4M conv=fsync status=progress
sync
echo "induo-write: done" >&2
