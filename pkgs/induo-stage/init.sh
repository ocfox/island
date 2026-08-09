#!/bin/sh
# PID 1 for the induo RAM stage. Nothing here touches the target disk; that
# only happens later, when induo-write is invoked over ssh.

export PATH=/bin
export HOME=/root

log() { echo "induo: $*" >&2; }

do_reboot() {
	sync
	reboot -f 2>/dev/null || echo b >/proc/sysrq-trigger
	# init must never exit, that is a kernel panic
	while :; do sleep 60; done
}

die() {
	log "FATAL: $*"
	log "disk untouched, rebooting into the previous system in 60s"
	sleep 60
	do_reboot
}

mount -t proc     proc     /proc
mount -t sysfs    sysfs    /sys
mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts /run/induo
mount -t devpts devpts /dev/pts
mount -t tmpfs  tmpfs  /run

timeout=1800
for a in $(cat /proc/cmdline); do
	case "$a" in
	induo.timeout=*) timeout="${a#induo.timeout=}" ;;
	esac
done

log "up (timeout=${timeout}s)"

for m in \
	virtio_pci virtio_net virtio_blk virtio_scsi virtio_mmio \
	xen_netfront xen_blkfront \
	e1000 e1000e igb igbvf ixgbe r8169 tg3 bnx2 bnx2x vmxnet3 \
	nvme ahci sd_mod sr_mod scsi_mod mptspi mpt3sas; do
	modprobe "$m" >/dev/null 2>&1 || true
done

ip link set lo up
[ -r /induo/net.sh ] || die "missing /induo/net.sh, config cpio was not prepended"
sh /induo/net.sh || die "network setup failed"

[ -s /root/.ssh/authorized_keys ] || die "no authorized_keys, nobody could log in"
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys

mkdir -p /etc/dropbear
dropbear -R -E -s -g -p 2222 || die "dropbear failed to start"

# Reboots back into the untouched original system if nobody shows up.
# induo-write drops /run/induo/active to stand this down.
(
	t=0
	while [ "$t" -lt "$timeout" ]; do
		[ -e /run/induo/active ] && exit 0
		sleep 5
		t=$((t + 5))
	done
	log "watchdog: idle for ${timeout}s, rebooting into previous system"
	do_reboot
) &

log "ready, waiting for ssh on port 2222"
ip -brief addr >&2

while :; do sleep 3600; done
