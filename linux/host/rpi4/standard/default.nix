{ lib, fetchgit, linux-ng
}:

with linux-ng;

let

  # TODO

  source = doSource {
    version = "5.4.0";
    extraVersion = "-rc8";
    src = builtins.fetchGit {
      url = https://git.research.arm.com/icecap/linux;
      ref = "icecap-rpi";
      rev = "d226de8664c62dcca31d228dcf04cb7b6a86d251";
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
  modules = true;
  dtbs = true;
}
