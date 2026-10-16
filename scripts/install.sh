#!/usr/bin/env bash
# sudo DISK=/dev/vda ./scripts/install.sh
# optional: INSTALL_HOSTNAME INSTALL_USERNAME SWAP_SIZE TIMEZONE CHEZMOI_REPO ALLOW_UNFREE CONFIRM=YES

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

[[ $EUID -eq 0 ]] || die "run as root"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FLAKE_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$FLAKE_ROOT"

command -v nix >/dev/null || die "nix not found"
command -v lsblk >/dev/null || die "lsblk not found"

# Installer ISO often has these off; http2=false avoids stalled cache downloads in VMs
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

info "will erase $DISK"
lsblk "$DISK" | sed 's/^/    /'
if [[ ${CONFIRM:-} != YES ]]; then
  read -r -p "Type YES to continue: " confirm
  [[ $confirm == YES ]] || die "aborted"
fi

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
  chezmoiRepo = "${CHEZMOI_REPO}";
  allowUnfree = ${ALLOW_UNFREE};
}
EOF

info "disko format+mount (LUKS passphrase next)"
info "first run downloads nixpkgs/disko — '0/N built' can sit for several minutes; not stuck"
info "watch traffic with: lsblk / ip / another TTY: journalctl -f"
nix --extra-experimental-features "nix-command flakes" run -L github:nix-community/disko -- \
  --flake "path:${FLAKE_ROOT}#${FLAKE_ATTR}" \
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

cp -a "${FLAKE_ROOT}/." /mnt/persist/etc/nixos/
[[ -f /mnt/persist/etc/nixos/settings.nix ]] || die "settings.nix missing after copy"

info "nixos-install"
if ! nixos-install --no-root-passwd --flake "path:${FLAKE_ROOT}#${FLAKE_ATTR}"; then
  echo "error: nixos-install failed" >&2
  echo "  if you saw 'NAR hash mismatch': bad/partial download — repair and retry:" >&2
  echo "    sudo nix-store --verify --check-contents --repair" >&2
  echo "    then re-run this script (or just nixos-install again)" >&2
  echo "  if you saw 'experimental feature': export NIX_CONFIG with nix-command flakes" >&2
  exit 1
fi

cat << EOF

done. detach ISO, reboot, unlock LUKS, log in as ${INSTALL_USERNAME}.
rebuilds: cd /persist/etc/nixos && sudo nixos-rebuild switch --flake path:.#${FLAKE_ATTR}

EOF
