{
  runCommand,
  writeText,
  makeInitrdNG,
  linuxPackages,
  pkgsStatic,
  grub2_efi,
  python3Packages,
  writers,
}:
let
  inherit (linuxPackages) kernel;
  ver = kernel.modDirVersion;

  modules = runCommand "induo-modules" { nativeBuildInputs = [ pkgsStatic.kmod ]; } ''
    src=${kernel.modules}/lib/modules/${ver}
    dst=$out/lib/modules/${ver}
    mkdir -p "$dst/kernel"

    for f in modules.builtin modules.builtin.modinfo modules.order; do
      if [ -e "$src/$f" ]; then cp "$src/$f" "$dst/$f"; fi
    done

    cp -r "$src/kernel" "$dst/"
    chmod -R u+w "$dst"
    rm -rf "$dst"/kernel/drivers/{gpu,media,sound,staging,iio,hid,infiniband,bluetooth,w1,hwmon}
    rm -rf "$dst"/kernel/drivers/net/{wireless,wwan,usb,can,ieee802154}
    rm -rf "$dst"/kernel/sound
    depmod -b "$out" ${ver}
  '';

  udhcpcScript = writeText "udhcpc.script" ''
    #!/bin/sh
    [ "$1" = "bound" ] || [ "$1" = "renew" ] || exit 0
    [ -n "$ip" ] && ip addr add "$ip/$mask" dev "$interface" 2>/dev/null || true
    [ -n "$router" ] && ip route add default via "$router" dev "$interface" onlink 2>/dev/null || true
  '';

  initScript = writeText "init" ''
    #!/bin/sh
    export PATH=/bin:/sbin

    mkdir -p /proc /sys /dev /run /tmp /etc /root /root/.ssh /etc/dropbear /etc/udhcpc
    mount -t proc proc /proc
    mount -t sysfs sysfs /sys
    mount -t devtmpfs devtmpfs /dev
    mkdir -p /dev/pts /dev/shm
    mount -t devpts devpts /dev/pts
    mount -t tmpfs tmpfs /run
    touch /run/induo-stage

    # Output directly to VNC virtual terminal tty0 and serial console
    exec >/dev/tty0 2>&1
    echo "=== INDUO RAM STAGE INIT ==="

    for m in virtio_pci virtio_net virtio_blk virtio_scsi sd_mod virtio_rng ena nvme nvme_core gve mana hv_netvsc hv_storvsc vmxnet3 vmw_pvscsi xen_netfront xen_blkfront xen_scsifront ixgbevf e1000e e1000 igb mlx4_en mlx5_core ahci ata_piix ata_generic; do
      modprobe $m 2>/dev/null || true
    done
    for a in $(cat /sys/bus/pci/devices/*/modalias /sys/bus/virtio/devices/*/modalias 2>/dev/null); do
      modprobe "$a" 2>/dev/null || true
    done
    mdev -s 2>/dev/null || true

    ip link set lo up

    for d in /sys/class/net/*; do
      name=$(basename "$d")
      if [ "$name" != "lo" ] && [ -d "$d" ]; then
        echo "induo: bringing up $name"
        ip link set "$name" up 2>/dev/null || true
        udhcpc -i "$name" -b -s /etc/udhcpc.script 2>/dev/null || true
      fi
    done

    if [ -f /induo/net.sh ]; then
      echo "induo: running /induo/net.sh"
      sh -x /induo/net.sh || echo "induo: net.sh failed" >&2
    fi

    echo "induo: network configuration:"
    ip addr
    ip -6 addr
    ip route
    ip -6 route

    chmod 700 /etc/dropbear 2>/dev/null || true
    chmod 600 /etc/dropbear/* 2>/dev/null || true
    chmod 700 /root /root/.ssh 2>/dev/null || true
    chmod 600 /root/.ssh/authorized_keys 2>/dev/null || true
    echo "induo: starting dropbear on 22 and 2222 with 8MB receive window"
    dropbear -E -s -g -W 8388608 -r /etc/dropbear/dropbear_ed25519_host_key -r /etc/dropbear/dropbear_rsa_host_key -p 22 -p 2222 &
    echo "=== INDUO RAM STAGE READY FOR SSH ==="

    TIMEOUT=180
    for arg in $(cat /proc/cmdline); do
      case "$arg" in
        induo.timeout=*) TIMEOUT="''${arg#induo.timeout=}" ;;
      esac
    done

    (
      t=0
      while [ "$t" -lt "$TIMEOUT" ]; do
        [ -f /run/active ] && exit 0
        sleep 5
        t=$((t + 5))
      done
      echo "induo: watchdog timeout, rebooting..."
      sync; reboot -f
    ) &

    while true; do
      sleep 3600
    done
  '';

  env = runCommand "induo-env" { } ''
    mkdir -p $out/bin
    for p in ${pkgsStatic.busybox} ${pkgsStatic.zstd} ${pkgsStatic.kmod} ${pkgsStatic.dropbear}; do
      for d in bin sbin; do
        [ -d "$p/$d" ] || continue
        for f in "$p/$d"/*; do
          ln -sf "$f" "$out/bin/$(basename "$f")"
        done
      done
    done
    install -m755 ${initScript} $out/init
  '';

  dropbearKeys = runCommand "induo-dropbear-keys" { nativeBuildInputs = [ pkgsStatic.dropbear ]; } ''
    mkdir -p $out
    dropbearkey -t ed25519 -f $out/dropbear_ed25519_host_key
    dropbearkey -t rsa -s 2048 -f $out/dropbear_rsa_host_key
  '';

  initrd = makeInitrdNG {
    name = "induo-initrd";
    compressor = "zstd";
    contents = [
      {
        source = "${env}/init";
        target = "/init";
      }
      {
        source = "${env}/bin";
        target = "/bin";
      }
      {
        source = "${modules}/lib/modules";
        target = "/lib/modules";
      }
      {
        source = "${dropbearKeys}/dropbear_ed25519_host_key";
        target = "/etc/dropbear/dropbear_ed25519_host_key";
      }
      {
        source = "${dropbearKeys}/dropbear_rsa_host_key";
        target = "/etc/dropbear/dropbear_rsa_host_key";
      }
      {
        source = writeText "passwd" "root:x:0:0:root:/root:/bin/sh\n";
        target = "/etc/passwd";
      }
      {
        source = writeText "shadow" "root:*:1:::::::\n";
        target = "/etc/shadow";
      }
      {
        source = writeText "group" "root:x:0:\n";
        target = "/etc/group";
      }
      {
        source = writeText "nsswitch.conf" "passwd: files\ngroup: files\nshadow: files\n";
        target = "/etc/nsswitch.conf";
      }
      {
        source = udhcpcScript;
        target = "/etc/udhcpc.script";
      }
    ];
  };

  grubEarlyCfg = writeText "grub-early.cfg" ''
    insmod all_video
    insmod gzio
    insmod part_gpt
    insmod part_msdos
    insmod ext2
    insmod xfs
    insmod btrfs
    search --no-floppy --file --set=root /induo/kernel
    if [ -f ($root)/boot/induo/kernel ]; then
      linux /boot/induo/kernel console=tty0 console=ttyS0,115200 panic=10 net.ifnames=0
      initrd /boot/induo/initrd
    else
      linux /induo/kernel console=tty0 console=ttyS0,115200 panic=10 net.ifnames=0
      initrd /induo/initrd
    fi
    boot
  '';

  grubEfi = runCommand "induo-grub-efi" { nativeBuildInputs = [ grub2_efi ]; } ''
    mkdir -p $out
    grub-mkstandalone \
      -O x86_64-efi \
      -o $out/grub.efi \
      --modules="normal minicmd serial ls echo test cat reboot halt linux search all_video part_msdos part_gpt fat ext2 xfs btrfs gzio zstd configfile" \
      "boot/grub/grub.cfg=${grubEarlyCfg}"
  '';

  stage = runCommand "induo-stage" { } ''
    mkdir -p $out
    ln -s ${kernel}/${kernel.target} $out/kernel
    ln -s ${initrd}/initrd $out/initrd
    ln -s ${grubEfi}/grub.efi $out/grub.efi
  '';
in
writers.writePython3Bin "induo" {
  flakeIgnore = [
    "E501"
    "E265"
    "E226"
  ];
  libraries = with python3Packages; [ rich ];
} (builtins.replaceStrings [ "@stage@" ] [ "${stage}" ] (builtins.readFile ./induo.py))
