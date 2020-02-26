# TODO fix and move to rshpkgs

{ lib, stdenv, buildPackages
, runCommand, runCommandCC, writeText, writeTextFile, writeScript, writeShellScriptBin, substituteAll
, writeScriptBin

, busybox, kmod
, rsync, cpio, gzip

, makeModulesClosure
, closureInfo
}:

{ compress ? "gzip -9n"
, default_console ? "tty1"

, modules ? null
, includeModules ? []
, loadModules ? []

, extraUtilsCommands ? ""
, extraInitCommands ? ""
, extraProfileCommands ? ""

, extraPasstru ? {}
}:

let
  allModules = includeModules ++ loadModules;
in

assert modules == null -> allModules == [];

with lib;

let

  modulesClosure = makeModulesClosure {
    rootModules = allModules;
    kernel = modules;
    firmware = modules;
    allowMissing = true;
  };

  # A utility for enumerating the shared-library dependencies of a program
  findLibs = buildPackages.writeShellScriptBin "find-libs" ''
    set -euo pipefail

    declare -A seen
    declare -a left

    patchelf="${buildPackages.patchelf}/bin/patchelf"

    function add_needed {
      rpath="$($patchelf --print-rpath $1)"
      dir="$(dirname $1)"
      for lib in $($patchelf --print-needed $1); do
        left+=("$lib" "$rpath" "$dir")
      done
    }

    add_needed $1

    while [ ''${#left[@]} -ne 0 ]; do
      next=''${left[0]}
      rpath=''${left[1]}
      ORIGIN=''${left[2]}
      left=("''${left[@]:3}")
      if [ -z ''${seen[$next]+x} ]; then
        seen[$next]=1

        # Ignore the dynamic linker which for some reason appears as a DT_NEEDED of glibc but isn't in glibc's RPATH.
        case "$next" in
          ld*.so.?) continue;;
        esac

        IFS=: read -ra paths <<< $rpath
        res=
        for path in "''${paths[@]}"; do
          path=$(eval "echo $path")
          if [ -f "$path/$next" ]; then
              res="$path/$next"
              echo "$res"
              add_needed "$res"
              break
          fi
        done
        if [ -z "$res" ]; then
          echo "Couldn't satisfy dependency $next" >&2
          exit 1
        fi
      fi
    done
  '';

  extraUtils = runCommandCC "extra-utils" {
    nativeBuildInputs = [ buildPackages.nukeReferences ];
    allowedReferences = [ "out" ]; # prevent accidents like glibc being included in the initrd
  } ''
    set +o pipefail

    mkdir -p $out/bin $out/lib
    ln -s $out/bin $out/sbin

    copy_bin_and_libs () {
      [ -f "$out/bin/$(basename $1)" ] && rm "$out/bin/$(basename $1)"
      cp -pdv $1 $out/bin
    }

    for f in ${busybox}/{s,}bin/*; do
      copy_bin_and_libs $f
    done

    copy_bin_and_libs ${kmod}/bin/kmod
    ln -sf kmod $out/bin/modprobe

    ${extraUtilsCommands}

    # Copy ld manually since it isn't detected correctly
    cp -pv ${stdenv.cc.libc.out}/lib/ld*.so.? $out/lib

    # Copy all of the needed libraries
    find $out/bin $out/lib -type f | while read BIN; do
      echo "Copying libs for executable $BIN"
      for LIB in $(${findLibs}/bin/find-libs $BIN); do
        TGT="$out/lib/$(basename $LIB)"
        if [ ! -f "$TGT" ]; then
          SRC="$(readlink -e $LIB)"
          cp -pdv "$SRC" "$TGT"
        fi
      done
    done

    # Strip binaries further than normal.
    chmod -R u+w $out
    stripDirs "$STRIP" "lib bin" "-s"

    # Run patchelf to make the programs refer to the copied libraries.
    find $out/bin $out/lib -type f | while read i; do
      if ! test -L $i; then
        nuke-refs -e $out $i
      fi
    done

    find $out/bin -type f | while read i; do
      if ! test -L $i; then
        echo "patching $i..."
        patchelf --set-interpreter $out/lib/ld*.so.? --set-rpath $out/lib $i || true
      fi
    done
  '';

  init = writeTextFile {
    name = "init";
    executable = true;
    checkPhase = ''
      ${buildPackages.busybox}/bin/ash -n $out
    '';
    text = ''
      #!${extraUtils}/bin/sh

      export LD_LIBRARY_PATH=${extraUtils}/lib
      export PATH=${extraUtils}/bin

      specialMount() {
        mkdir -m 0755 -p "$2"
        mount -n -t "$4" -o "$3" "$1" "$2"
      }
      specialMount proc /proc nosuid,noexec,nodev proc
      specialMount sysfs /sys nosuid,noexec,nodev sysfs
      specialMount devtmpfs /dev nosuid,strictatime,mode=755,size=5% devtmpfs
      specialMount devpts /dev/pts nosuid,noexec,mode=620,ptmxmode=0666 devpts
      specialMount tmpfs /run nosuid,nodev,strictatime,mode=755,size=25% tmpfs

      console=${default_console}
      for o in $(cat /proc/cmdline); do
        case $o in
          console=*)
            set -- $(IFS==; echo $o)
            params=$2
            set -- $(IFS=,; echo $params)
            console=$1
            ;;
          init=*)
            set -- $(IFS==; echo $o)
            next_init=$2
            ;;
        esac
      done

      interact() {
        setsid sh -c "ash -l </dev/$console >/dev/$console 2>/dev/$console"
      }

      fail() {
        echo "Failed. Starting interactive shell..." >/dev/$console
        interact
      }
      trap fail 0

      mkdir -p /lib
      echo ${extraUtils}/bin/modprobe > /proc/sys/kernel/modprobe
      ${optionalString (modules != null) ''
        ln -s ${modulesClosure}/lib/modules /lib/modules
        ln -s ${modulesClosure}/lib/firmware /lib/firmware
        for m in ${concatStringsSep " " loadModules}; do
          echo "loading module $m..."
          modprobe $m
        done
      ''}

      ${extraInitCommands}

      interact
    '';
  };

  profile = writeText "profile" ''
    ${extraProfileCommands}
  '';

  closure = closureInfo {
    rootPaths = [
      init
      profile
    ];
  };

in runCommand "initrd.gz" {
  nativeBuildInputs = [ rsync cpio gzip ];
  passthru = {
    inherit init modulesClosure extraUtils;
  } // extraPasstru;
} ''
  mkdir -p root/etc
  ln -s ${init} root/init
  ln -s ${profile} root/etc/profile
  (cd root && cp -prd --parents $(cat ${closure}/store-paths) .)
  (cd root && find * -print0 | xargs -0r touch -h -d '@1')
  (cd root && find * -print0 | sort -z | cpio -o -H newc -R +0:+0 --reproducible --null | ${compress} > $out)
''
