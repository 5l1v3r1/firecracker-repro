{ lib, fetchgit, linux-ng
}:

with linux-ng;

let

  source = doSource {
    version = "5.6.0";
    extraVersion = "-rc3";
    src = builtins.fetchGit {
      url = https://github.com/torvalds/linux;
      rev = "f8788d86ab28f61f7b46eb6be375f8a726783636";
    };
  };

  config = makeConfig {
    inherit source;
    target = "defconfig";
  };

in
doKernel rec {
  inherit source config;
  modules = false;
}
