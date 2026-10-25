{ pkgs, lib, ... }:

{
  # lanzaboote replaces systemd-boot and signs UKIs. keys live on /persist
  # because / is wiped on every boot. losing this directory means re-enrolling.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/persist/etc/secureboot";

    # automatic provisioning (trust on first use): the first boot is unsigned,
    # a service generates keys, re-signs the ESP, and reboots. systemd-boot then
    # enrolls the keys, which only works with the firmware in Setup Mode.
    autoGenerateKeys.enable = true;
    autoEnrollKeys = {
      enable = true;
      autoReboot = true;
    };

    # TPM2 policy through systemd-pcrlock, updated by lanzaboote on rebuilds
    measuredBoot = {
      enable = true;
      pcrs = [
        0
        4
        7
      ];
    };
  };

  security.tpm2.enable = true;

  environment.systemPackages = [
    pkgs.sbctl
    pkgs.tpm2-tools
    (pkgs.writeShellScriptBin "enroll-tpm" ''
      set -euo pipefail
      [[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
      dev=''${1:-$(readlink -f /dev/disk/by-partlabel/disk-main-luks)}

      if ! ${pkgs.systemd}/bin/bootctl status 2>/dev/null | grep -q 'Secure Boot: enabled'; then
        echo "Secure Boot is not enabled yet. Finish key enrollment first." >&2
        exit 1
      fi
      if [[ $(${pkgs.systemd}/lib/systemd/systemd-pcrlock is-supported) != yes ]]; then
        echo "this TPM is not supported by systemd-pcrlock" >&2
        exit 1
      fi

      echo "Recovery key (write it down, it is shown once):"
      ${pkgs.systemd}/bin/systemd-cryptenroll --recovery-key "$dev"
      ${pkgs.systemd}/bin/systemd-cryptenroll \
        --tpm2-device=auto --tpm2-with-pin=true \
        --tpm2-pcrlock=/var/lib/systemd/pcrlock.json "$dev"
    '')
  ];
}
