#!/usr/bin/env bash
# Gum front-end for install.sh. Falls back to plain install.sh if gum is unavailable.
# sudo ./scripts/tui.sh

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

[[ $EUID -eq 0 ]] || die "run as root (sudo ./scripts/tui.sh)"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FLAKE_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$FLAKE_ROOT"

[[ -f $SCRIPT_DIR/install.sh ]] || die "install.sh missing"
chmod +x "$SCRIPT_DIR/install.sh"

export NIX_CONFIG="${NIX_CONFIG-}
experimental-features = nix-command flakes
http2 = false
download-attempts = 5
connect-timeout = 10
"

# Prefer real gum; otherwise nix run (installer ISO has nix, not gum)
gum() {
  if [[ -n ${GUM_BIN:-} ]]; then
    "$GUM_BIN" "$@"
  else
    command gum "$@"
  fi
}

ensure_gum() {
  if command -v gum >/dev/null; then
    GUM_BIN=$(command -v gum)
    return
  fi
  command -v nix >/dev/null || die "need gum or nix to fetch gum"
  info "fetching gum via nix…"
  # Resolve once so later prompts are snappy
  GUM_BIN=$(nix build --no-link --print-out-paths nixpkgs#gum)/bin/gum
  [[ -x $GUM_BIN ]] || die "failed to build gum"
}

fallback_plain() {
  info "gum unavailable or no TTY — using plain install.sh"
  exec "$SCRIPT_DIR/install.sh"
}

[[ -t 0 && -t 1 ]] || fallback_plain
ensure_gum || fallback_plain

gum style --border rounded --padding "0 2" --border-foreground 212 \
  "EphemeralOS install" "LUKS + btrfs + impermanence"

# --- disk ---
if [[ -z ${DISK:-} ]]; then
  mapfile -t disk_rows < <(lsblk -d -n -o NAME,SIZE,MODEL,TRAN,TYPE | awk '$5=="disk" {print}')
  [[ ${#disk_rows[@]} -gt 0 ]] || die "no disks found"

  choices=()
  for row in "${disk_rows[@]}"; do
    name=$(awk '{print $1}' <<<"$row")
    choices+=("/dev/$name  $row")
  done

  picked=$(gum choose --header "Whole disk to erase:" "${choices[@]}") || die "aborted"
  DISK=$(awk '{print $1}' <<<"$picked")
fi

[[ -b $DISK ]] || die "not a block device: $DISK"

# --- desktop ---
if [[ -z ${INSTALL_DESKTOP:-} ]]; then
  desk=$(gum choose --header "Desktop:" \
    "plasma  — KDE Plasma 6" \
    "gnome   — GNOME" \
    "niri    — niri + Noctalia shell") || die "aborted"
  INSTALL_DESKTOP=$(awk '{print $1}' <<<"$desk")
fi

# --- identity / knobs ---
INSTALL_HOSTNAME=$(gum input --header "Hostname" --value "${INSTALL_HOSTNAME:-nixos}" --placeholder "nixos")
INSTALL_USERNAME=$(gum input --header "Username" --value "${INSTALL_USERNAME:-nixuser}" --placeholder "nixuser")
SWAP_SIZE=$(gum input --header "Swap size" --value "${SWAP_SIZE:-4G}" --placeholder "4G")
TIMEZONE=$(gum input --header "Timezone" --value "${TIMEZONE:-UTC}" --placeholder "UTC")
CHEZMOI_REPO=$(gum input --header "chezmoi repo (optional)" --value "${CHEZMOI_REPO:-}" --placeholder "https://github.com/you/dotfiles.git")
ALLOW_UNFREE=$(gum choose --header "Allow unfree packages?" "true" "false")

[[ -n $INSTALL_HOSTNAME ]] || die "hostname empty"
[[ -n $INSTALL_USERNAME ]] || die "username empty"
[[ -n $SWAP_SIZE ]] || die "swap size empty"
[[ -n $TIMEZONE ]] || die "timezone empty"

gum style --border rounded --padding "0 2" --border-foreground 196 \
  "WILL ERASE: $DISK" \
  "desktop=$INSTALL_DESKTOP  host=$INSTALL_HOSTNAME  user=$INSTALL_USERNAME" \
  "swap=$SWAP_SIZE  tz=$TIMEZONE  unfree=$ALLOW_UNFREE"

gum confirm "Erase $DISK and install?" || die "aborted"

export DISK
export INSTALL_HOSTNAME
export INSTALL_USERNAME
export INSTALL_DESKTOP
export SWAP_SIZE
export TIMEZONE
export CHEZMOI_REPO
export ALLOW_UNFREE
export FLAKE_ATTR="${FLAKE_ATTR:-nixos}"
export CONFIRM=YES

exec "$SCRIPT_DIR/install.sh"
