# Installer ISO. Online install: the flake is embedded, nixpkgs is fetched.
{
  lib,
  pkgs,
  modulesPath,
  flakeSrc,
  ...
}:

let
  # keep machine-specific files out of the image when built from a path: flake
  src = lib.cleanSourceWith {
    src = flakeSrc;
    filter =
      path: _:
      !(builtins.elem (baseNameOf path) [
        "settings.json"
        "settings.nix"
        "hardware-configuration.nix"
      ])
      && !(lib.hasPrefix "result" (baseNameOf path));
  };
in

{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  isoImage.edition = "ephemeral";

  environment.systemPackages = with pkgs; [
    git
    gum
    sbctl
    tpm2-tools
    btrfs-progs
    cryptsetup
    # the scripts chmod themselves, so run them from a writable copy
    (writeShellScriptBin "ephemeral-install" ''
      set -euo pipefail
      dir=$(mktemp -d /tmp/ephemeral-nixos.XXXXXX)
      cp -rT /etc/ephemeral-nixos "$dir"
      chmod -R u+w "$dir"
      exec "$dir/scripts/tui.sh" "$@"
    '')
  ];

  environment.etc."ephemeral-nixos".source = src;

  environment.shellInit = ''
    if [ "$(tty)" = /dev/tty1 ] && [ -z "''${EPHEMERAL_HINT_SHOWN:-}" ]; then
      export EPHEMERAL_HINT_SHOWN=1
      echo "Install: sudo ephemeral-install   (UEFI, TPM2, Secure Boot in Setup Mode)"
    fi
  '';
}
