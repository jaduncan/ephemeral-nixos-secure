# Installer ISO: nix build path:.#iso
# Boots the minimal NixOS installer with this flake at /etc/ephemeral-nixos.
# The install itself still downloads from cache.nixos.org.
{
  lib,
  pkgs,
  modulesPath,
  flakeSrc,
  ...
}:

let
  # machine files and build results stay out of the image
  src = lib.cleanSourceWith {
    src = lib.cleanSource flakeSrc;
    filter =
      path: _:
      let
        name = baseNameOf path;
      in
      !(builtins.elem name [
        "settings.json"
        "settings.nix"
        "hardware-configuration.nix"
      ])
      && !(lib.hasPrefix "result" name);
  };
in
{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  isoImage.edition = "ephemeral";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.etc."ephemeral-nixos".source = src;

  environment.systemPackages = [
    pkgs.git
    pkgs.gum
    # the scripts chmod themselves, which fails in the read-only store
    (pkgs.writeShellApplication {
      name = "ephemeral-install";
      runtimeInputs = [ pkgs.coreutils ];
      text = ''
        dir=$(mktemp -d /tmp/ephemeral-nixos.XXXXXX)
        cp -rT /etc/ephemeral-nixos "$dir"
        chmod -R u+w "$dir"
        exec "$dir/scripts/tui.sh" "$@"
      '';
    })
  ];

  services.getty.helpLine = ''

    Install: sudo ephemeral-install
    Needs UEFI, a TPM2, and Secure Boot in Setup Mode.
  '';
}
