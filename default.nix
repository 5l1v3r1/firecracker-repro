let
  pkgs = import ./nixpkgs {
    crossSystem = {
      system = "aarch64-linux";
      config = "aarch64-unknown-linux-gnu";
    };
    overlays = [
      (import ./nixpkgs-linux-ng/overlay.nix)
      (import ./overlay.nix)
    ];
  };

in pkgs
