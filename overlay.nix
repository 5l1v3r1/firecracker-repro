self: super: with self;

{

  firecracker-repro =
    let
      mk = config: lib.makeScope newScope (callPackage ./scope.nix {} config);
    in {
      virt = mk {
        plat = "virt";
        # host_kernel = "ubuntu";
        host_kernel = "standard";
        guest_kernel = "firecracker";
      };
      rpi4 = mk {
        plat = "rpi4";
        host_kernel = "ubuntu";
        # host_kernel = "standard";
        # guest_kernel = "firecracker";
        guest_kernel = "standard";
      };
    };

  v = firecracker-repro.virt;
  r = firecracker-repro.rpi4;

}
