{ lib, pkgs, buildPackages
, runCommand, writeText, writeScript, runtimeShell, buildEnv
, linux-ng, dtb-helpers, raspberry-pi-firmware
, busybox
}:

config:

with lib;
self: with self;

let
  local_config = {
    nfs_dev = "10.2.15.47:/export/nix/store";
  };

in
{
  runPkgs = buildPackages;

  firecracker-prebuilt = callPackage ./firecracker-prebuilt.nix {};

  busybox_static = busybox.override {
    enableStatic = true;
    useMusl = true;
  };

  mk_initramfs = callPackage ./initramfs/mk-initramfs.nix {};
  mk_modules_closure = callPackage ./initramfs/mk-modules-closure.nix {};

  host_kernel = callPackage (./linux/host + "/${config.plat}/${config.host_kernel}") {};
  host_kernel_path = host_kernel.kernel;
  # host_kernel_path = ./tmp/linux/arch/arm64/boot/Image;

  host_kernel_params = [
    "init=${host_next_init}"
    "loglevel=7"
    # "lamekaslr"
  ] ++ lib.optionals (config.plat == "virt") [
    "console=ttyAMA0"
  ] ++ lib.optionals (config.plat == "rpi4") [
    "console=ttyS0,115200" # NOTE firmware was silently changing ttyAMA in cmdline.txt to ttyS0 in device tree
  ];

  guest_kernel = callPackage (./linux/guest + "/${config.guest_kernel}") {};
  # guest_kernel_path = guest_kernel.kernel;
  guest_kernel_path = ./tmp/linux/arch/arm64/boot/Image;

  guest_kernel_params = [
    "keep_bootcon"
    "console=ttyS0"
    "reboot=k"
    "panic=1"
    "pci=off"
    "loglevel=8"
    "lamekaslr"
  ];

  guest_initramfs = mk_initramfs {
    extraInitCommands = ''
      echo running
    '';
  };

  guest_config = pkgs.writeText "config.json" ''
    {
      "boot-source": {
        "kernel_image_path": "${guest_kernel_path}",
        "boot_args": "${lib.concatStringsSep " " guest_kernel_params}",
        "initrd_path": "${guest_initramfs}"
      },
      "machine-config": {
        "vcpu_count": 1,
        "mem_size_mib": 512
      },
      "drives": [
      ],
      "logger": {
        "log_fifo": "/proc/self/fd/2",
        "metrics_fifo": "metrics_fifo",
        "level": "Debug"
      }
    }
  '';

  run_guest = writeScript "run-guest" ''
    #!${runtimeShell}
    touch metrics_fifo
    ${firecracker-prebuilt}/bin/firecracker \
      --seccomp-level 0 \
      --config-file ${guest_config} \
      --no-api
  '';

  run = runCommand "run" {} ''
    mkdir $out
    ${lib.concatStrings (lib.mapAttrsToList (k: v: ''
      ln -s ${v} $out/${k}
    '') links)}
  '';

} // lib.optionalAttrs (config.plat == "virt") {

  links = {
    "host_vmlinux" = "${host_kernel.dev}/vmlinux";
    "guest_vmlinux" = "${guest_kernel.dev}/vmlinux";
    run = run_sh;
  };

  run_sh = writeScript "run.sh" (with runPkgs; ''
    #!${runtimeShell}
    debug=
    if [ "$1" = "d" ]; then
      debug="-s -S"
    fi

    ${runPkgs.qemu-aarch64}/bin/qemu-system-aarch64 \
      -machine virt,virtualization=on \
      -cpu cortex-a72 \
      -m 2048 \
      -nographic \
      -serial mon:stdio \
      -device virtio-9p-device,mount_tag=store,fsdev=store \
      -fsdev local,id=store,security_model=none,readonly,path=/nix/store \
      -kernel ${host_kernel_path} \
      -initrd ${host_initramfs} \
      -append '${lib.concatStringsSep " " host_kernel_params}' \
      $debug
  '');

} // lib.optionalAttrs (config.plat == "rpi4") {

  config_txt = writeText "config.txt" ''
    enable_uart=1
    enable_gic=1
    arm_64bit=1
    kernel=kernel
    initramfs initrd followkernel
  '';

  cmdline_txt = writeText "cmdline.txt" ''
    ${lib.concatStringsSep " " host_kernel_params}
  '';

  boot = runCommand "boot" {} ''
    mkdir $out
    mkdir $out/overlays
    ln -s ${raspberry-pi-firmware}/*.* $out
    ln -s ${raspberry-pi-firmware}/overlays/*.* $out/overlays
    rm $out/kernel*.img
    ln -sf ${config_txt} $out/config.txt
    ln -sf ${cmdline_txt} $out/cmdline.txt
    ln -sf ${host_kernel_path} $out/kernel
    ln -sf ${host_initramfs} $out/initrd
  '';

  syncSimple = src: writeScript "sync" ''
    #!${runPkgs.runtimeShell}
    set -e

    # if [ -z "$1" ]; then
    #   echo "usage: $0 DEV" >&2
    #   exit 1
    # fi

    # dev="$1"

    dev=/dev/disk/by-label/icecap-boot

    mkdir -p mnt
    sudo mount $dev ./mnt
    sudo rm -r ./mnt/* || true
    sudo cp -rvL ${src}/* ./mnt
    sudo umount ./mnt
  '';

  sync = syncSimple boot;

  links = {
    run = sync;
  };

} // {

} // {

  host_initramfs =
    let
      qif = "eth0";
      udhcpc_sh = writeScript "udhcpc.sh" ''
        #!${host_initramfs.extraUtils}/bin/sh
        if [ "$1" = bound ]; then
          ip address add "$ip/$mask" dev "$interface"
          if [ -n "$mtu" ]; then
            ip link set mtu "$mtu" dev "$interface"
          fi
          if [ -n "$staticroutes" ]; then
            echo "$staticroutes" \
              | sed -r "s@(\S+) (\S+)@ ip route add \"\1\" via \"\2\" dev \"$interface\" ; @g" \
              | sed -r "s@ via \"0\.0\.0\.0\"@@g" \
              | /bin/sh
          fi
          if [ -n "$router" ]; then
            ip route add "$router" dev "$interface" # just in case if "$router" is not within "$ip/$mask" (e.g. Hetzner Cloud)
            ip route add default via "$router" dev "$interface"
          fi
          if [ -n "$dns" ]; then
            rm -f /etc/resolv.conf
            for i in $dns; do
              echo "nameserver $dns" >> /etc/resolv.conf
            done
          fi
        fi
      '';
    in
      mk_initramfs {
          extraUtilsCommands = ''
            copy_bin_and_libs ${pkgs.curl.bin}/bin/curl
            copy_bin_and_libs ${pkgs.mkinitcpio-nfs-utils}/bin/ipconfig
            copy_bin_and_libs ${pkgs.iproute}/bin/ip
            copy_bin_and_libs ${pkgs.strace}/bin/strace
            copy_bin_and_libs ${pkgs.netcat}/bin/nc
            cp -pdv ${pkgs.libunwind}/lib/libunwind-aarch64*.so* $out/lib
            cp -pdv ${pkgs.glibc}/lib/libnss_dns*.so* $out/lib
          '';
          extraInitCommands = ''
            target_root=/mnt-root
            mkdir -p $target_root
            mount -n -t tmpfs -o nosuid,nodev,strictatime tmpfs $target_root

            nix_store_mnt=$target_root/nix/store
            mkdir -p $nix_store_mnt

            ${{
              virt = ''
                mount -t 9p -o trans=virtio,version=9p2000.L,ro store $nix_store_mnt
              '';
              rpi4 = ''
                echo "setting up ${qif}..."
                ip link set ${qif} up

                mkdir -p /etc /bin
                ln -s $(which sh) /bin/sh
                udhcpc --quit --now -i ${qif} -O staticroutes --script ${udhcpc_sh}

                mount -t nfs -o nolock,ro ${local_config.nfs_dev} $nix_store_mnt
              '';
            }.${config.plat}}

            if [ ! -e "$target_root/$next_init" ] && [ ! -L "$target_root/$next_init" ] ; then
                echo "next init script ($target_root/$next_init) not found"
                fail
            fi

            moveMount() {
              mkdir -m 0755 -p "$target_root/$1"
              mount --move "$1" "$target_root/$1"
            }
            moveMount /proc
            moveMount /sys
            moveMount /dev
            moveMount /run

            ${{
              virt = ''
              '';
              rpi4 = ''
                mkdir -p $target_root/etc
                cp /etc/resolv.conf $target_root/etc
              '';
            }.${config.plat}}

            echo "switching root..."

            exec env -i console=$console $(type -P switch_root) "$target_root" "$next_init"
            fail
          '';
          extraProfileCommands = ''
          '';
        };

  host_next_init =
    let
      env = with pkgs; buildEnv {
        name = "env";
        ignoreCollisions = true;
        paths = map (setPrio 8) [
          acl
          attr
          # bashInteractive # bash with ncurses support
          coreutils-full
          curl
          diffutils
          findutils
          gawk
          stdenv.cc.libc
          gnugrep
          gnupatch
          gnused
          less
          ncurses
          netcat
          procps
          strace
          su
          time
          utillinux
          which # 88K size

          iproute
          iperf
          iptables
          nftables
        ] ++ [
          (setPrio 9 busybox)
        ];
        postBuild = ''
          # Remove wrapped binaries, they shouldn't be accessible via PATH.
          find $out/bin -maxdepth 1 -name ".*-wrapped" -type l -delete
        '';
      };
      profile = writeText "profile" ''
        x() {
          ${run_guest}
        }
      '';
    in
      with pkgs; writeScript "init" ''
        #!${runtimeShell}
        export PATH=${env}/bin
        export LS_COLORS=

        mkdir -p /etc /bin
        ln -s ${busybox}/bin/sh /bin/sh

        ln -s ${profile} /etc/profile

        mkdir -p /tmp

        ${run_guest}

        setsid sh -c "ash -l </dev/$console >/dev/$console 2>/dev/$console"
      '';

}
