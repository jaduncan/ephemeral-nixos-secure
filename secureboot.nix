{ lib, pkgs, ... }:

{
  # lanzaboote signs the boot chain and replaces the systemd-boot module
  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.lanzaboote = {
    enable = true;
    # persisted in persist.nix
    pkiBundle = "/var/lib/sbctl";

    # trust on first use: the first boot is unsigned. a service generates the
    # keys, stages them on the ESP, re-signs it and reboots, and systemd-boot
    # enrolls them. enrollment needs the firmware in Setup Mode.
    autoGenerateKeys.enable = true;
    autoEnrollKeys = {
      enable = true;
      autoReboot = true;
    };
  };

  environment.systemPackages = [ pkgs.sbctl ];
}
