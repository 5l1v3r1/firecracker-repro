{ lib, fetchgit, linux-ng
}:

with linux-ng;

let

  # source = doSource {
  #   version = "5.6.0";
  #   extraVersion = "-rc3";
  #   src = builtins.fetchGit {
  #     url = https://github.com/torvalds/linux;
  #     rev = "f8788d86ab28f61f7b46eb6be375f8a726783636";
  #   };
  # };

  # config = makeConfig {
  #   inherit source;
  #   target = "defconfig";
  # };

  source = doSource {
    version = "5.6.0";
    extraVersion = "-rc2";
    src = builtins.fetchGit {
      url = https://github.com/raspberrypi/linux;
      ref = "rpi-5.6.y";
      rev = "9c4d22e9ec1201355491f8cd72be4c5e7f85683e";
    };
  };

  # source = doSource {
  #   version = "5.5.6";
  #   src = builtins.fetchGit {
  #     url = https://github.com/raspberrypi/linux;
  #     ref = "rpi-5.5.y";
  #     rev = "51298607ca6307b9f91c6bee8ea3c4d89e5c9f05";
  #   };
  # };

  # source = doSource {
  #   version = "5.4.22";
  #   src = builtins.fetchGit {
  #     url = https://github.com/raspberrypi/linux;
  #     ref = "rpi-5.4.y";
  #     rev = "6c5efcf09c40d37f72692fdbdf6d461abede20f1";
  #   };
  # };

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
  dtbs = true;
  modules = false;
}
