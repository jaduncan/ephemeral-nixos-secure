{ pkgs, lib, ... }:

{
  # lanzaboote replaces systemd-boot and signs UKIs. keys live on /persist
  # because / is wiped on every boot. losing this directory means re-enrolling.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/persist/etc/secureboot";
    autoGenerateKeys.enable = true;
    # only takes effect when the firmware is in Setup Mode
    autoEnrollKeys = {
      enable = true;
      autoReboot = false;
    };
  };

  # TPM2 for the LUKS unlock (see enroll-tpm below) and measured boot
  security.tpm2.enable = true;
  boot.initrd.systemd.tpm2.enable = true;

  environment.systemPackages = [
    pkgs.sbctl
    pkgs.tpm2-tools
    (pkgs.writeShellScriptBin "enroll-tpm" ''
      set -euo pipefail
      [[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
      dev=''${1:-$(readlink -f /dev/disk/by-partlabel/disk-main-luks)}

      if ! ${pkgs.systemd}/bin/bootctl status 2>/dev/null | grep -q 'Secure Boot: enabled'; then
        echo "Secure Boot is not enabled. Enroll keys and reboot first, otherwise PCR 7 will change." >&2
        exit 1
      fi

      echo "Recovery key (write it down, it is shown once):"
      ${pkgs.systemd}/bin/systemd-cryptenroll --recovery-key "$dev"
      ${pkgs.systemd}/bin/systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 "$dev"
      echo "done. next boot unlocks via TPM; changing firmware or Secure Boot keys falls back to the passphrase."
    '')
  ];
}
