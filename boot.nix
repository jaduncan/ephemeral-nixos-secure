{
  ...
}:

{
  boot = {
    # bootloader is lanzaboote, see secureboot.nix
    loader.systemd-boot.editor = false;
    loader.systemd-boot.configurationLimit = 5;
    initrd.systemd.enable = true;
    loader.efi.canTouchEfiVariables = true;
    loader.timeout = 3;

    plymouth.enable = true;

    consoleLogLevel = 3;
    kernelParams = [
      "quiet"
      "splash"
      "rd.udev.log_level=3"
      "rd.systemd.show_status=auto"
      # "plymouth.use-simpledrm"
    ];

    tmp.useTmpfs = true;
    tmp.cleanOnBoot = true;

    initrd.systemd.services.rollback = {
      description = "Rollback Btrfs root to blank snapshot";
      wantedBy = [ "initrd.target" ];
      after = [ "systemd-cryptsetup@cryptroot.service" ];
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        set -euo pipefail
        mkdir -p /btrfs_tmp
        mount -o subvolid=5 /dev/mapper/cryptroot /btrfs_tmp
        trap 'umount /btrfs_tmp' EXIT

        if [[ ! -e /btrfs_tmp/root-blank ]]; then
          echo "ERROR: root-blank subvolume missing" >&2
          exit 1
        fi

        if [[ -e /btrfs_tmp/root ]]; then
          # higher id is a newer child, so delete from the bottom
          list=$(btrfs subvolume list -o /btrfs_tmp/root)
          if [[ -n $list ]]; then
            mapfile -t subvols < <(printf '%s\n' "$list" | cut -d' ' -f9-)
            for ((i = ''${#subvols[@]} - 1; i >= 0; i--)); do
              subvolume=''${subvols[i]}
              [[ -n $subvolume ]] || continue
              btrfs subvolume delete "/btrfs_tmp/$subvolume"
            done
          fi
          btrfs subvolume delete /btrfs_tmp/root
        fi

        btrfs subvolume snapshot /btrfs_tmp/root-blank /btrfs_tmp/root
      '';
    };

    supportedFilesystems = [
      "btrfs"
      "ntfs"
      "exfat"
      "vfat"
    ];
  };

  services.fstrim.enable = true;

  systemd.sleep.settings.Sleep = {
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };
}
