{ lib, buildPackages, runCommand, writeText
, buildEnv
, busybox
, linux-ng
, dtb-helpers
, runtimeShell
, writeScript
, pkgs
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

  busybox_static = busybox.override {
    enableStatic = true;
    useMusl = true;
  };

  mk_initramfs = callPackage ./initramfs/mk-initramfs.nix {};
  mk_modules_closure = callPackage ./initramfs/mk-modules-closure.nix {};

  guest_kernel = callPackage (./linux/guest + "/${config.guest_kernel}") {};

  host_kernel = callPackage (./linux/host + "/${config.plat}/${config.host_kernel}") {};

  host_kernel_params = [
    "init=${host_next_init}"
    "loglevel=7"
    "console=ttyAMA0"
  ];

  run = runCommand "run" {} ''
    mkdir $out
    ${lib.concatStrings (lib.mapAttrsToList (k: v: ''
      ln -s ${v} $out/${k}
    '') links)}
  '';

  # .

  # linux = callPackage ./linux {};

} // lib.optionalAttrs (config.plat == "virt") {

  links = {
    "vmlinux" = "${host_kernel.dev}/vmlinux";
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
      -kernel ${host_kernel.kernel} \
      -initrd ${host_initramfs} \
      -append '${lib.concatStringsSep " " host_kernel_params}'
  '');

} // {

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
        }
      '';
          # ${test.test} &
    in
      with pkgs; writeScript "init" ''
        #!${runtimeShell}
        export PATH=${env}/bin
        export LS_COLORS=

        mkdir -p /etc /bin
        ln -s ${busybox}/bin/sh /bin/sh

        ln -s ${profile} /etc/profile

        # for iperf
        mkdir -p /tmp

        setsid sh -c "ash -l </dev/$console >/dev/$console 2>/dev/$console"
      '';
        # ${test.test}

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
      # initramfs = nx.config.build.initramfs;
      mk_initramfs {
          # modules = host_modules;
          # loadModules = [ "genet" ];
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

            echo "setting up ${qif}..."
            ip link set ${qif} up

            mkdir -p /etc /bin
            ln -s $(which sh) /bin/sh
            udhcpc --quit --now -i ${qif} -O staticroutes --script ${udhcpc_sh}

            nix_store_mnt=$target_root/nix/store
            mkdir -p $nix_store_mnt
            ${{
              virt = ''
                mount -t 9p -o trans=virtio,version=9p2000.L,ro store $nix_store_mnt
              '';
              rpi4 = ''
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

            mkdir -p $target_root/etc
            cp /etc/resolv.conf $target_root/etc

            echo "switching root..."

            exec env -i console=$console $(type -P switch_root) "$target_root" "$next_init"
            fail
          '';
          extraProfileCommands = ''
          '';
        };

}
