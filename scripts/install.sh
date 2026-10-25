#!/usr/bin/env bash
# sudo DISK=/dev/vda ./scripts/install.sh
# optional: INSTALL_* SWAP_SIZE TIMEZONE CHEZMOI_REPO FLAKE_INPUTS=lock|update CONFIRM=YES

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[[ $EUID -eq 0 ]] || die "run as root"
require_uefi

FLAKE_ROOT=$(cd "$(dirname "$SCRIPT_DIR")" && pwd)
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
CHEZMOI_REV=${CHEZMOI_REV:-}
FLAKE_ATTR=${FLAKE_ATTR:-nixos}
FLAKE_INPUTS=${FLAKE_INPUTS:-lock}

if [[ -z ${DISK:-} ]]; then
  info "disks:"
  lsblk -dpn -o NAME,TYPE,SIZE,TRAN,MODEL | awk '$2=="disk"{print}' | sed 's/^/    /'
  echo
  read -r -p "whole disk (e.g. /dev/vda): " DISK
fi

validate_disk "$DISK"

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

validate_desktop "$INSTALL_DESKTOP"
validate_hostname "$INSTALL_HOSTNAME"
validate_username "$INSTALL_USERNAME"
validate_swap "$SWAP_SIZE"
validate_timezone "$TIMEZONE"
validate_chezmoi "$CHEZMOI_REPO"
if [[ -n $CHEZMOI_REPO ]]; then
  [[ -n $CHEZMOI_REV ]] || die "CHEZMOI_REV is required with CHEZMOI_REPO"
  validate_chezmoi_rev "$CHEZMOI_REV"
fi
validate_flake_inputs "$FLAKE_INPUTS"
validate_flake_attr "$FLAKE_ATTR"
info "desktop=$INSTALL_DESKTOP inputs=$FLAKE_INPUTS"

info "will erase $DISK"
lsblk "$DISK" | sed 's/^/    /'
if [[ ${CONFIRM:-} != YES ]]; then
  read -r -p "Type YES to continue: " confirm
  [[ $confirm == YES ]] || die "aborted"
fi

STAGE=""
cleanup() {
  # Always leave STAGE before deleting — a deleted cwd breaks getcwd / nix.
  if [[ -n ${STAGE:-} && -d ${STAGE:-} ]]; then
    cd / || true
    rm -rf "$STAGE"
  fi
}
trap cleanup EXIT

STAGE=$(mktemp -d /tmp/nixos-flake-stage.XXXXXX)
info "staging flake at $STAGE"

# Copy sources only — skip build products / VCS / local machine files
tar -C "$FLAKE_ROOT" \
  --exclude='.git' \
  --exclude='result' \
  --exclude='result-*' \
  --exclude='.direnv' \
  --exclude='settings.json' \
  --exclude='settings.nix' \
  --exclude='hardware-configuration.nix' \
  -cf - . | tar -C "$STAGE" -xf -

cd "$STAGE"

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

# values reach nix through the environment, so nothing needs escaping
# shellcheck disable=SC2016 # the ${...} below is nix interpolation
S_HOSTNAME=$INSTALL_HOSTNAME S_USERNAME=$INSTALL_USERNAME S_DISK=$DISK \
  S_SWAP=$SWAP_SIZE S_TZ=$TIMEZONE S_DESKTOP=$INSTALL_DESKTOP \
  nix eval --impure --raw --expr '
    let
      e = builtins.getEnv;
      fields = [
        [ "hostname" (e "S_HOSTNAME") ]
        [ "username" (e "S_USERNAME") ]
        [ "diskDevice" (e "S_DISK") ]
        [ "swapSize" (e "S_SWAP") ]
        [ "timeZone" (e "S_TZ") ]
        [ "desktop" (e "S_DESKTOP") ]
      ];
      line = f: "  ${builtins.toJSON (builtins.elemAt f 0)}: ${builtins.toJSON (builtins.elemAt f 1)}";
    in
    "{\n" + builtins.concatStringsSep ",\n" (map line fields) + "\n}\n"
  ' >settings.json

case $FLAKE_INPUTS in
  update)
    info "updating flake inputs to newest (nix flake update)"
    nix flake update
    ;;
  lock)
    if [[ ! -f flake.lock ]]; then
      info "no flake.lock — creating one"
      nix flake lock
    else
      info "using flake.lock pins"
    fi
    ;;
esac

# disko tool from flake.lock, same rev the config evaluates against
info "disko format+mount (LUKS passphrase next)"
info "first run downloads nixpkgs/disko — can sit on 0/N for several minutes"
nix run -L --inputs-from "path:${STAGE}" disko -- \
  --flake "path:${STAGE}#${FLAKE_ATTR}" \
  --mode destroy,format,mount

findmnt /mnt >/dev/null 2>&1 || die "/mnt is not mounted after disko"
findmnt /mnt/persist >/dev/null 2>&1 || die "/mnt/persist is not mounted after disko"
findmnt /mnt/boot >/dev/null 2>&1 || die "/mnt/boot is not mounted after disko"
btrfs subvolume list /mnt | grep -q 'root-blank' || die "root-blank missing after disko"

mkdir -p /mnt/persist/passwords /mnt/persist/etc/ssh /mnt/persist/etc/nixos
chmod 700 /mnt/persist/passwords
chmod 755 /mnt/persist/etc/ssh
# activation chowns this. it has to exist on /persist before the bind mount.
install -d -m 0700 "/mnt/persist/home/${INSTALL_USERNAME}"
if [[ -n $CHEZMOI_REPO ]]; then
  (
    umask 077
    printf '%s\n' "$CHEZMOI_REPO $CHEZMOI_REV" > /mnt/persist/etc/chezmoi-repo
  )
  chmod 600 /mnt/persist/etc/chezmoi-repo
fi

info "login password for ${INSTALL_USERNAME}"
if command -v mkpasswd >/dev/null; then
  HASH=$(mkpasswd -m yescrypt)
else
  HASH=$(nix shell --inputs-from "path:${STAGE}" nixpkgs#mkpasswd -c mkpasswd -m yescrypt)
fi
[[ -n $HASH ]] || die "empty password hash (mkpasswd failed or cancelled)"

# Restrictive umask so the hash is never world-readable, even briefly
(
  umask 077
  printf '%s\n' "$HASH" > "/mnt/persist/passwords/${INSTALL_USERNAME}"
)
chmod 600 "/mnt/persist/passwords/${INSTALL_USERNAME}"
sync

# Copy staged flake onto the target (already without .git)
tar -C "$STAGE" -cf - . | tar -C /mnt/persist/etc/nixos -xf -
[[ -f /mnt/persist/etc/nixos/settings.json ]] || die "settings.json missing after copy"
[[ -f /mnt/persist/etc/nixos/flake.nix ]] || die "flake.nix missing after copy"

# Leave deleted directories before nixos-install (getcwd safety)
cd /
cleanup
trap - EXIT
STAGE=""

info "nixos-install from /mnt/persist/etc/nixos"
if ! nixos-install --no-root-passwd --flake "path:/mnt/persist/etc/nixos#${FLAKE_ATTR}"; then
  echo "error: nixos-install failed" >&2
  echo "  retry (if /mnt still mounted):" >&2
  echo "    cd / && sudo nixos-install --no-root-passwd --flake path:/mnt/persist/etc/nixos#${FLAKE_ATTR}" >&2
  echo "  store repair: sudo nix-store --verify --check-contents --repair" >&2
  exit 1
fi

cat << EOF

done. detach ISO, reboot, unlock LUKS, log in as ${INSTALL_USERNAME}.
rebuilds: cd /persist/etc/nixos && sudo nixos-rebuild switch --flake path:.#${FLAKE_ATTR}

EOF
