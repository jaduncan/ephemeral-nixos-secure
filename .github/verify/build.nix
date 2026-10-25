# Small derivations worth building in CI (scripts run shellcheck at build time).
{ flake }:

let
  inherit (flake.inputs.nixpkgs) lib;
  pick =
    name: pkgs:
    lib.findFirst (p: lib.getName p == name) (throw "${name} not in systemPackages") pkgs;
  system = flake.nixosConfigurations.nixos.config;
  iso = flake.packages.x86_64-linux.iso;
in
[
  (pick "enroll-tpm" system.environment.systemPackages)
]
