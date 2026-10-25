{ settings, ... }:

{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = settings.diskDevice;
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              extraFormatArgs = [
                "--type"
                "luks2"
                "--pbkdf"
                "argon2id"
                "--iter-time"
                "5000"
              ];
              settings.allowDiscards = true;
              # falls back to the passphrase prompt when no TPM slot is enrolled
              # or the PCR 7 policy no longer matches
              crypttabExtraOpts = [
                "tpm2-device=auto"
                "token-timeout=10"
              ];
              content = {
                type = "btrfs";
                extraArgs = [
                  "-L"
                  "nixos"
                  "-f"
                ];
                postCreateHook = ''
                  set -euo pipefail
                  MNTPOINT=$(mktemp -d)
                  mount /dev/mapper/cryptroot "$MNTPOINT" -o subvol=/
                  cleanup() {
                    status=$?
                    umount "$MNTPOINT" || true
                    rmdir "$MNTPOINT" || true
                    exit "$status"
                  }
                  trap cleanup EXIT
                  btrfs subvolume snapshot -r "$MNTPOINT/root" "$MNTPOINT/root-blank"
                '';
                subvolumes = {
                  "/root" = {
                    mountpoint = "/";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                  "/nix" = {
                    mountpoint = "/nix";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                  "/persist" = {
                    mountpoint = "/persist";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                  "/log" = {
                    mountpoint = "/var/log";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                  "/swap" = {
                    mountpoint = "/.swapvol";
                    swap.swapfile.size = settings.swapSize;
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
