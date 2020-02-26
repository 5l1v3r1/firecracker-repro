{ lib, fetchgit, fetchFromGitHub, linux-ng
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

  config = "${firecracker-source}/resources/microvm-kernel-aarch64-config";

  firecracker-source = fetchFromGitHub {
    repo = "firecracker";
    owner = "firecracker-microvm";
    rev = "8d48e730f2ea8fe524002643912049486e07528c";
    sha256 = "04xfzxxww0rxaf244javvx59z3541d8a9vgmvfvkysqff6lzwf89";
  };

  # config = ./firecracker.config;

in
doKernel rec {
  inherit source config;
  modules = false;
  passthru = {
    defconfig = savedefconfig {
      inherit source config;
    };
  };
}
