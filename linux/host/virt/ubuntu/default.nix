{ lib, fetchgit, linux-ng
}:

with linux-ng;

let

  # source = linux_kernel_unified_source;

  # source = doSource {
  #   version = "5.3.18";
  #   src = builtins.fetchGit {
  #     url = https://github.com/raspberrypi/linux;
  #     ref = "rpi-5.3.y";
  #     rev = "32ba05a62a8071d091d7582cc37b4bac2962b1dd";
  #   };
  #   patches = with kernelPatches; [
  #     scriptconfig
  #   ];
  # };

  # source = doSource {
  #   version = "5.6.0";
  #   extraVersion = "-rc3";
  #   src = builtins.fetchGit {
  #     url = https://github.com/torvalds/linux;
  #     rev = "f8788d86ab28f61f7b46eb6be375f8a726783636";
  #   };
  # };

  source = doSource {
    version = "5.3.18";
    src = builtins.fetchGit {
      url = https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux.git;
      ref = "linux-5.3.y";
      rev = "d4f3318ed8fab6316cb7a269b8f42306632a3876";
    };
  };

  config = makeConfig {
    inherit source;
    target = "alldefconfig";
    allconfig = ./defconfig;
  };

in
doKernel rec {
  inherit source config;
  # modules = true;
  modules = false;
  dtbs = false;
  # dtbs = true;
}
