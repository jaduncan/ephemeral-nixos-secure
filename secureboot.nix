{
  config,
  pkgs,
  lib,
  ...
}:

let
  # systemd-pcrlock writes this atomically (temp file + rename), which breaks
  # on an impermanence bind mount or symlink. it holds the NV index and the
  # recovery PIN needed to update the policy, so it has to survive reboots.
  # a real /persist path also keeps the copy written during nixos-install.
  pcrlockPolicy = "/persist/var/lib/pcrlock/pcrlock.json";
  systemd = config.systemd.package;
in

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
    # needs a TPM supported by systemd-pcrlock, also at install time
    measuredBoot = {
      enable = true;
      inherit pcrlockPolicy;
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

      if ! ${systemd}/bin/bootctl status 2>/dev/null | grep -q 'Secure Boot: enabled'; then
        echo "Secure Boot is not enabled yet. Finish key enrollment first." >&2
        exit 1
      fi
      if [[ $(${systemd}/lib/systemd/systemd-pcrlock is-supported) != yes ]]; then
        echo "this TPM is not supported by systemd-pcrlock" >&2
        exit 1
      fi

      # re-run lanzaboote so PCR 4 measurements and the policy match this boot
      /run/current-system/bin/switch-to-configuration boot

      echo "Recovery key (write it down, it is shown once):"
      ${systemd}/bin/systemd-cryptenroll --recovery-key "$dev"
      ${systemd}/bin/systemd-cryptenroll \
        --wipe-slot=tpm2 --tpm2-device=auto --tpm2-with-pin=true \
        --tpm2-pcrlock=${pcrlockPolicy} "$dev"
    '')
  ];
}
