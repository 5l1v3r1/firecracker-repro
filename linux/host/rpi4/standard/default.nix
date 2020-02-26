{ lib, fetchgit, linux-ng
, linux_kernel_unified_source
}:

with linux-ng;

let

  source = doSource {
    version = "5.4.0";
    extraVersion = "-rc8";
    src = builtins.fetchGit {
      url = https://git.research.arm.com/icecap/linux;
      ref = "icecap-rpi";
      # rev = "b8a649685560f5bf04cb6eddce4490477fd22191";
      rev = "d226de8664c62dcca31d228dcf04cb7b6a86d251";
    };
  };

  # config = makeConfig {
  #   inherit source;
  #   target = "bcm2711_defconfig";
  # };

  config = makeConfig {
    inherit source;
    target = "alldefconfig";
    allconfig = ./defconfig;
  };

in
doKernel rec {
  inherit source config;
  modules = true;
  dtbs = true;
}
