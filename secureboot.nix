{
  config,
  lib,
  pkgs,
  ...
}:

let
  systemd = config.systemd.package;

  # systemd-pcrlock replaces this file atomically, which fails through an
  # impermanence bind mount, so it lives on /persist directly. it holds the NV
  # index and recovery PIN that later policy updates need. the initrd gets its
  # own copy from the ESP (loader/credentials/pcrlock.*.cred).
  pcrlockPolicy = "/persist/var/lib/pcrlock/pcrlock.json";

  # upstream pcrlock units only order after var.mount, not the persist bind
  # mounts, and would write to the wiped root
  pcrlockUnits = [
    "systemd-pcrlock-firmware-code"
    "systemd-pcrlock-firmware-config"
    "systemd-pcrlock-secureboot-policy"
    "systemd-pcrlock-secureboot-authority"
    "systemd-pcrlock-make-policy"
  ];
in
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

    # TPM2 policy kept up to date by lanzaboote on every rebuild. needs a TPM
    # that systemd-pcrlock supports, also during nixos-install. PCR 0 changes
    # with firmware updates; unlock falls back to the passphrase until the next
    # rebuild after one.
    measuredBoot = {
      enable = true;
      pcrs = [
        0
        4
        7
      ];
      inherit pcrlockPolicy;
    };
  };

  systemd.services = lib.genAttrs pcrlockUnits (_: {
    unitConfig.RequiresMountsFor = [
      "/var/lib/pcrlock.d"
      (dirOf pcrlockPolicy)
    ];
  });

  environment.systemPackages = [
    pkgs.sbctl
    (pkgs.writeShellApplication {
      name = "enroll-tpm";
      runtimeInputs = [
        systemd
        pkgs.coreutils
        pkgs.gnugrep
      ];
      text = ''
        # bind LUKS to the measured boot policy, with a PIN, and add a recovery key
        [[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
        dev=$(readlink -f "''${1:-/dev/disk/by-partlabel/disk-main-luks}")

        if ! bootctl status 2>/dev/null | grep -q 'Secure Boot: enabled'; then
          echo "Secure Boot is not enabled yet; wait for key enrollment to finish" >&2
          exit 1
        fi
        if [[ $(${systemd}/lib/systemd/systemd-pcrlock is-supported) != yes ]]; then
          echo "this TPM is not supported by systemd-pcrlock" >&2
          exit 1
        fi

        # re-run lanzaboote so the PCR 4 predictions and policy match this boot
        /run/current-system/bin/switch-to-configuration boot

        echo "Recovery key (shown once, write it down):"
        systemd-cryptenroll --recovery-key "$dev"
        systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-with-pin=true \
          --tpm2-pcrlock=${pcrlockPolicy} "$dev"
      '';
    })
  ];
}
