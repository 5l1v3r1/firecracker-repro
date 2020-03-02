# Nix expressions for reproducing [Firecracker](https://github.com/firecracker-microvm/firecracker) issues

[Nix](https://nixos.org/nix/) enables the precise description of reproducable build environments and artifacts. This repository contains artifacts for reproducing [Firecracker](https://github.com/firecracker-microvm/firecracker) issues.

There are two ways to obtain the artifacts described in this repository:
    - [Install Nix](https://nixos.org/nix/download.html) and then follow the build instructions below, or
    - Ask me to provide them directly.

## Reproducing [#1634](https://github.com/firecracker-microvm/firecracker/issues/1634) on QEMU

First, build:
```
$ nix-build -A v.run
$ ls ./result
guest_vmlinux  host_vmlinux  run
```
The target of the new symlink `./result` contains a `vmlinux` with debugging symbols for both the host and the guest kernel, along with a script to run Firecracker in a `qemu-system-aarch64 -machine virt` virtual machine.
The script just invokes QEMU.
To reproduce the issue, run:
```
$ ./result/run
```
To debug the QEMU VM using GDB, run:
```
$ ./result/run d
```
Attach to the GDB server with something like:
```
$ gdb -ex 'target remote :1234'
```
