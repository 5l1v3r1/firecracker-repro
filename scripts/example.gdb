set pagination off

add-symbol-file ./result/host_vmlinux 0xffff800010081000
b kvm_vm_ioctl_create_vcpu
c
clear
remove-symbol-file -a 0xffff800010081000

add-symbol-file ./tmp/linux/vmlinux 0xffffe0000fe81000
b start_kernel
c
clear

set pagination on
layout src
