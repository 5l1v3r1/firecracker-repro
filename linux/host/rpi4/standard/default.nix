{ lib, fetchgit, linux-ng
}:

with linux-ng;

let

  source = doSource {
    version = "5.6.0";
    extraVersion = "-rc2";
    src = builtins.fetchGit {
      url = https://github.com/raspberrypi/linux;
      ref = "rpi-5.6.y";
      rev = "9c4d22e9ec1201355491f8cd72be4c5e7f85683e";
    };
  };

  config = makeConfig {
    inherit source;
    target = "defconfig";
  };

in
doKernel rec {
  inherit source config;
  dtbs = true;
}
