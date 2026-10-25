# Installer ISO. Online install: the flake is embedded, nixpkgs is fetched.
{
  pkgs,
  modulesPath,
  flakeSrc,
  ...
}:

{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  isoImage.isoName = "ephemeral-nixos-secure.iso";
  isoImage.edition = "ephemeral";

  environment.systemPackages = with pkgs; [
    git
    gum
    sbctl
    tpm2-tools
    btrfs-progs
    cryptsetup
  ];

  # read-only copy of this repo; install.sh stages its own writable copy
  environment.etc."ephemeral-nixos".source = flakeSrc;

  environment.shellInit = ''
    if [ "$(tty)" = /dev/tty1 ] && [ -z "''${EPHEMERAL_HINT_SHOWN:-}" ]; then
      export EPHEMERAL_HINT_SHOWN=1
      echo "Install: sudo /etc/ephemeral-nixos/scripts/tui.sh   (UEFI, Secure Boot in Setup Mode)"
    fi
  '';
}
