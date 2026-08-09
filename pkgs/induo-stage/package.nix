{
  runCommand,
  writeText,
  makeInitrdNG,
  linuxPackages,
  pkgsStatic,
  busybox,
  coreutils,
  iproute2,
  dropbear,
  zstd,
  kmod,
}:
let
  kernel = linuxPackages.kernel;
  ver = kernel.modDirVersion;

  modules = runCommand "induo-modules" { nativeBuildInputs = [ kmod ]; } ''
    src=${kernel.modules}/lib/modules/${ver}
    dst=$out/lib/modules/${ver}
    mkdir -p "$dst/kernel"

    for f in modules.builtin modules.builtin.modinfo modules.order; do
      if [ -e "$src/$f" ]; then cp "$src/$f" "$dst/$f"; fi
    done

    for d in drivers/net drivers/block drivers/scsi drivers/ata drivers/nvme \
             drivers/virtio drivers/message drivers/xen lib crypto; do
      if [ -e "$src/kernel/$d" ]; then
        mkdir -p "$dst/kernel/$(dirname "$d")"
        cp -r "$src/kernel/$d" "$dst/kernel/$d"
      fi
    done

    chmod -R u+w "$dst"

    # Most of drivers/net by size, and none of it can be a VPS uplink.
    rm -rf "$dst"/kernel/drivers/net/{wireless,wwan,usb,can,ieee802154}

    depmod -b "$out" ${ver}

    # An empty tree still produces a valid depmod result and an initrd that
    # silently has no drivers, so check that the copy actually found something.
    if [ -z "$(find "$dst" -name 'virtio_net.ko*' -print -quit)" ]; then
      echo "induo-stage: no virtio_net module, the kernel module layout changed" >&2
      exit 1
    fi
  '';

  # busybox first so the real coreutils and iproute2 win the name clashes;
  # busybox's ip cannot express onlink routes.
  env = runCommand "induo-env" { } ''
    mkdir -p $out/bin
    for p in ${busybox} ${coreutils} ${zstd} ${kmod} ${iproute2} ${dropbear}; do
      for d in bin sbin; do
        [ -d "$p/$d" ] || continue
        for f in "$p/$d"/*; do
          ln -sf "$f" "$out/bin/$(basename "$f")"
        done
      done
    done
    install -m755 ${./write.sh} $out/bin/induo-write
    install -m755 ${./init.sh} $out/init
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
        source = writeText "passwd" "root:x:0:0:root:/root:/bin/sh\n";
        target = "/etc/passwd";
      }
      {
        source = writeText "group" "root:x:0:\n";
        target = "/etc/group";
      }
    ];
  };
in
runCommand "induo-stage" { meta.description = "Kernel, initrd and kexec for the induo RAM stage"; }
  ''
    mkdir -p $out
    ln -s ${kernel}/${kernel.target} $out/kernel
    ln -s ${initrd}/initrd $out/initrd
    ln -s ${pkgsStatic.kexec-tools}/bin/kexec $out/kexec
  ''
