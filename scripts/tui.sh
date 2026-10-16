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

# Charm apps are happier than raw linux console TERM in VMs
case ${TERM:-} in
  linux | dumb | "" ) export TERM=xterm-256color ;;
esac

fallback_plain() {
  info "${1:-gum unavailable} — using plain install.sh"
  exec "$SCRIPT_DIR/install.sh"
}

[[ -t 0 && -t 1 ]] || fallback_plain "no TTY"

# Resolve a real gum binary only (type -P ignores functions/aliases)
GUM_BIN=$(type -P gum 2>/dev/null || true)
if [[ -z ${GUM_BIN:-} ]]; then
  command -v nix >/dev/null || fallback_plain "need gum or nix"
  info "fetching gum via nix…"
  GUM_BIN=$(nix build --no-link --print-out-paths nixpkgs#gum)/bin/gum
fi
[[ -x ${GUM_BIN:-} ]] || fallback_plain "gum binary missing"

run_gum() { "$GUM_BIN" "$@"; }

# Probe — Bubble Tea/gum sometimes dies on odd consoles; fall back cleanly
if ! run_gum style "ok" >/dev/null 2>&1; then
  fallback_plain "gum failed on this terminal"
fi

run_gum style --border rounded --padding "0 2" --border-foreground 212 \
  "EphemeralOS install" "LUKS + btrfs + impermanence"

# --- disk ---
# NAME/TYPE first so MODEL spaces don't break field parsing
if [[ -z ${DISK:-} ]]; then
  mapfile -t disk_paths < <(lsblk -dpn -o NAME,TYPE | awk '$2 == "disk" { print $1 }')
  [[ ${#disk_paths[@]} -gt 0 ]] || die "no disks found (lsblk -dpn -o NAME,TYPE)"

  choices=()
  for path in "${disk_paths[@]}"; do
    meta=$(lsblk -dn -o SIZE,TRAN,MODEL "$path" 2>/dev/null | sed 's/[[:space:]]\+/ /g')
    choices+=("$path  $meta")
  done

  picked=$(run_gum choose --header "Whole disk to erase:" "${choices[@]}") || die "aborted"
  DISK=$(awk '{print $1}' <<<"$picked")
fi

[[ -b $DISK ]] || die "not a block device: $DISK"

# --- desktop ---
if [[ -z ${INSTALL_DESKTOP:-} ]]; then
  desk=$(run_gum choose --header "Desktop:" \
    "plasma  — KDE Plasma 6" \
    "gnome   — GNOME" \
    "niri    — niri + Noctalia shell") || die "aborted"
  INSTALL_DESKTOP=$(awk '{print $1}' <<<"$desk")
fi

# --- identity / knobs ---
INSTALL_HOSTNAME=$(run_gum input --header "Hostname" --value "${INSTALL_HOSTNAME:-nixos}" --placeholder "nixos")
INSTALL_USERNAME=$(run_gum input --header "Username" --value "${INSTALL_USERNAME:-nixuser}" --placeholder "nixuser")
SWAP_SIZE=$(run_gum input --header "Swap size" --value "${SWAP_SIZE:-4G}" --placeholder "4G")
TIMEZONE=$(run_gum input --header "Timezone" --value "${TIMEZONE:-UTC}" --placeholder "UTC")
CHEZMOI_REPO=$(run_gum input --header "chezmoi repo (optional)" --value "${CHEZMOI_REPO:-}" --placeholder "https://github.com/you/dotfiles.git")
ALLOW_UNFREE=$(run_gum choose --header "Allow unfree packages?" "true" "false")

[[ -n $INSTALL_HOSTNAME ]] || die "hostname empty"
[[ -n $INSTALL_USERNAME ]] || die "username empty"
[[ -n $SWAP_SIZE ]] || die "swap size empty"
[[ -n $TIMEZONE ]] || die "timezone empty"

run_gum style --border rounded --padding "0 2" --border-foreground 196 \
  "WILL ERASE: $DISK" \
  "desktop=$INSTALL_DESKTOP  host=$INSTALL_HOSTNAME  user=$INSTALL_USERNAME" \
  "swap=$SWAP_SIZE  tz=$TIMEZONE  unfree=$ALLOW_UNFREE"

run_gum confirm "Erase $DISK and install?" || die "aborted"

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
