#!/usr/bin/env bash
# sudo DISK=/dev/vda ./scripts/install.sh
# optional: INSTALL_HOSTNAME INSTALL_USERNAME INSTALL_DESKTOP SWAP_SIZE TIMEZONE CHEZMOI_REPO ALLOW_UNFREE CONFIRM=YES

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

[[ $EUID -eq 0 ]] || die "run as root"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FLAKE_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$FLAKE_ROOT"

command -v nix >/dev/null || die "nix not found"
command -v lsblk >/dev/null || die "lsblk not found"

export NIX_CONFIG="${NIX_CONFIG-}
experimental-features = nix-command flakes
http2 = false
download-attempts = 5
connect-timeout = 10
"

INSTALL_HOSTNAME=${INSTALL_HOSTNAME:-nixos}
INSTALL_USERNAME=${INSTALL_USERNAME:-nixuser}
SWAP_SIZE=${SWAP_SIZE:-4G}
TIMEZONE=${TIMEZONE:-UTC}
CHEZMOI_REPO=${CHEZMOI_REPO:-}
ALLOW_UNFREE=${ALLOW_UNFREE:-true}
FLAKE_ATTR=${FLAKE_ATTR:-nixos}

if [[ -z ${DISK:-} ]]; then
  info "disks:"
  lsblk -d -o NAME,SIZE,MODEL,TRAN,TYPE | sed 's/^/    /'
  echo
  read -r -p "whole disk (e.g. /dev/vda): " DISK
fi

[[ -b $DISK ]] || die "not a block device: $DISK"
[[ $DISK =~ p?[0-9]+$ && ! $DISK =~ nvme[0-9]+n[0-9]+$ && ! $DISK =~ mmcblk[0-9]+$ ]] \
  && die "looks like a partition: $DISK"

if [[ -z ${INSTALL_DESKTOP:-} ]]; then
  echo
  info "desktop environment:"
  echo "  1) plasma  — KDE Plasma 6"
  echo "  2) gnome   — GNOME"
  echo "  3) niri    — niri + Noctalia shell"
  echo
  read -r -p "Choice [1]: " desk_choice
  case ${desk_choice:-1} in
    1 | plasma | Plasma | kde | KDE) INSTALL_DESKTOP=plasma ;;
    2 | gnome | Gnome | GNOME) INSTALL_DESKTOP=gnome ;;
    3 | niri | Niri) INSTALL_DESKTOP=niri ;;
    *) die "invalid desktop choice: ${desk_choice}" ;;
  esac
fi
case $INSTALL_DESKTOP in
  plasma | gnome | niri) ;;
  *) die "INSTALL_DESKTOP must be plasma, gnome, or niri (got: $INSTALL_DESKTOP)" ;;
esac
info "desktop=$INSTALL_DESKTOP"

info "will erase $DISK"
lsblk "$DISK" | sed 's/^/    /'
if [[ ${CONFIRM:-} != YES ]]; then
  read -r -p "Type YES to continue: " confirm
  [[ $confirm == YES ]] || die "aborted"
fi

# --- Build a non-git staging tree (avoids path:/... hash mismatch with dirty git) ---
STAGE=$(mktemp -d /tmp/nixos-flake-stage.XXXXXX)
info "staging flake at $STAGE"
cp -a "$FLAKE_ROOT"/. "$STAGE/"
rm -rf "$STAGE/.git"
rm -f "$STAGE/flake.lock"
cd "$STAGE"

cp -f settings.example.nix settings.nix
cp -f hardware-configuration.example.nix hardware-configuration.nix

if lsblk -d -o TRAN -n "$DISK" 2>/dev/null | grep -qi virtio \
  || [[ $DISK == /dev/vd* ]]; then
  info "virtio disk — writing guest hardware-configuration.nix"
  cat > hardware-configuration.nix << 'EOF'
{ config, lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];
  boot.initrd.availableKernelModules = [
    "virtio_pci" "virtio_scsi" "virtio_blk" "virtio_net"
    "xhci_pci" "usb_storage" "sd_mod" "sr_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
EOF
fi

cat > settings.nix << EOF
{
  hostname = "${INSTALL_HOSTNAME}";
  username = "${INSTALL_USERNAME}";
  diskDevice = "${DISK}";
  swapSize = "${SWAP_SIZE}";
  timeZone = "${TIMEZONE}";
  desktop = "${INSTALL_DESKTOP}";
  chezmoiRepo = "${CHEZMOI_REPO}";
  allowUnfree = ${ALLOW_UNFREE};
}
EOF

info "locking flake inputs (in staging dir only)"
nix flake lock

info "disko format+mount (LUKS passphrase next)"
info "first run downloads nixpkgs/disko — can sit on 0/N for several minutes"
# Installer ISO Nix often rejects --no-write-lock-file; lock already written above.
nix run -L github:nix-community/disko -- \
  --flake "path:${STAGE}#${FLAKE_ATTR}" \
  --mode destroy,format,mount

btrfs subvolume list /mnt | grep -q 'root-blank' || die "root-blank missing after disko"

mkdir -p /mnt/persist/passwords /mnt/persist/etc/ssh /mnt/persist/etc/nixos
chmod 700 /mnt/persist/passwords
chmod 755 /mnt/persist/etc/ssh

info "login password for ${INSTALL_USERNAME}"
if command -v mkpasswd >/dev/null; then
  HASH=$(mkpasswd -m sha-512)
else
  HASH=$(nix-shell -p mkpasswd --run 'mkpasswd -m sha-512')
fi
printf '%s\n' "$HASH" > "/mnt/persist/passwords/${INSTALL_USERNAME}"
chmod 600 "/mnt/persist/passwords/${INSTALL_USERNAME}"

cp -a "$STAGE"/. /mnt/persist/etc/nixos/
[[ -f /mnt/persist/etc/nixos/settings.nix ]] || die "settings.nix missing after copy"

info "nixos-install from staging path $STAGE"
if ! nixos-install --no-root-passwd --flake "path:${STAGE}#${FLAKE_ATTR}"; then
  echo "error: nixos-install failed" >&2
  echo "  path hash mismatch: use a copy without .git (this script stages to $STAGE)" >&2
  echo "  store NAR mismatch: sudo nix-store --verify --check-contents --repair" >&2
  exit 1
fi

cat << EOF

done. detach ISO, reboot, unlock LUKS, log in as ${INSTALL_USERNAME}.
rebuilds: cd /persist/etc/nixos && sudo nixos-rebuild switch --flake path:.#${FLAKE_ATTR}

EOF
