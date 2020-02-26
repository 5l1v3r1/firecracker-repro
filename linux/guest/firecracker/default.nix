{ lib, fetchgit, linux-ng
}:

with linux-ng;

let

  source = doSource {
    version = "4.14.0";
    src = builtins.fetchGit {
      url = https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux.git;
      ref = "linux-4.14.y";
      rev = "bebc6082da0a9f5d47a1ea2edc099bf671058bd4";
    };
  };

  config = ./firecracker.config;

in
doKernel rec {
  inherit source config;
  # modules = true;
  modules = false;
  dtbs = false;
  passthru = {
    defconfig = savedefconfig {
      inherit source config;
    };
  };
}
