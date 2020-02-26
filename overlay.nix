self: super: with self;

{

  mk_firecracker_repro = config: lib.makeScope newScope (callPackage ./scope.nix {} config);

  firecracker_repro = lib.mapAttrs (_: mk_firecracker_repro) {
    virt = {
      plat = "virt";
      # host_kernel = "ubuntu";
      host_kernel = "standard";
      # guest_kernel = "firecracker";
      guest_kernel = "standard";
    };
    rpi4 = {
      plat = "rpi4";
      # host_kernel = "ubuntu";
      host_kernel = "standard";
      guest_kernel = "firecracker";
      # guest_kernel = "standard";
    };
  };

  v = firecracker_repro.virt;
  r = firecracker_repro.rpi4;

}
