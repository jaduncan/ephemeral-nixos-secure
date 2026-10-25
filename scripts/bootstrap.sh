#!/usr/bin/env bash
# Plain installer (no gum). TUI path: bootstrap-tui.sh / tui.sh
# curl -fsSL https://raw.githubusercontent.com/the-wittch/ephemeral-nixos/main/scripts/bootstrap.sh \
#   | sudo env SWAP_SIZE=4G bash -s -- /dev/vda

set -euo pipefail

SCRIPT_DIR=""
src=${BASH_SOURCE[0]:-}
if [[ -n $src && -f $src && $src != /dev/fd/* ]]; then
  SCRIPT_DIR=$(cd "$(dirname "$src")" && pwd)
fi

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

# Prefer shared validators when running from a real checkout
if [[ -n $SCRIPT_DIR && -f $SCRIPT_DIR/common.sh ]]; then
  # shellcheck source=common.sh
  source "$SCRIPT_DIR/common.sh"
fi

DEFAULT_REPO_URL="https://github.com/the-wittch/ephemeral-nixos.git"

REPO_URL="${REPO_URL:-$DEFAULT_REPO_URL}"
# TAG wins over BRANCH (both work with git clone --branch; tags are preferred for pins)
BRANCH="${TAG:-${BRANCH:-main}}"
EXPECTED_REV="${EXPECTED_REV:-}"

[[ $EUID -eq 0 ]] || die "need root (use: curl ... | sudo env ... bash -s -- /dev/DISK)"

export NIX_CONFIG="${NIX_CONFIG-}
experimental-features = nix-command flakes
http2 = false
download-attempts = 5
connect-timeout = 10
"

DISK="${1:-${DISK:-}}"
[[ -n $DISK ]] || die "usage: bash -s -- /dev/vda"
if declare -F validate_disk >/dev/null; then
  validate_disk "$DISK"
else
  [[ -b $DISK ]] || die "not a block device: $DISK"
fi

if declare -F require_uefi >/dev/null; then
  require_uefi
elif [[ ! -d /sys/firmware/efi ]]; then
  die "UEFI required (enable OVMF/UEFI in the VM/firmware)"
fi

info "REPO_URL=$REPO_URL"
info "REF=$BRANCH"
[[ -n $EXPECTED_REV ]] && info "EXPECTED_REV=$EXPECTED_REV"
info "DISK=$DISK"

FLAKE_ROOT=""
if [[ -n $SCRIPT_DIR && -f $SCRIPT_DIR/../flake.nix ]]; then
  FLAKE_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
  info "local flake: $FLAKE_ROOT"
fi

if [[ -z $FLAKE_ROOT ]]; then
  if [[ $REPO_URL == *YOUR_USER* || $REPO_URL == *YOUR_REPO* ]]; then
    die "REPO_URL still looks like a placeholder: $REPO_URL"
  fi
  command -v git >/dev/null || die "git not found"

  FLAKE_ROOT=$(mktemp -d /tmp/nixos-flake.XXXXXX)
  info "cloning $REPO_URL (ref $BRANCH) → $FLAKE_ROOT"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$FLAKE_ROOT" \
    || die "git clone failed (check URL/tag/branch and network)"
fi

[[ -f $FLAKE_ROOT/scripts/install.sh ]] || die "install.sh missing in clone"
[[ -f $FLAKE_ROOT/scripts/common.sh ]] || die "common.sh missing in clone"
[[ -f $FLAKE_ROOT/flake.nix ]] || die "flake.nix missing in clone"
chmod +x "$FLAKE_ROOT/scripts/install.sh"

# checked here, not by code from the clone being checked
if [[ -n $EXPECTED_REV ]]; then
  [[ $EXPECTED_REV =~ ^[0-9a-fA-F]{40}$ ]] \
    || die "EXPECTED_REV must be the full 40-character commit hash"
  got=$(git -C "$FLAKE_ROOT" rev-parse HEAD)
  [[ $got == "${EXPECTED_REV,,}" ]] \
    || die "git rev mismatch: got $got, expected $EXPECTED_REV. Refusing to install."
  info "verified git rev $got"
elif [[ $BRANCH != main ]]; then
  info "warning: $BRANCH is not verified (set EXPECTED_REV)"
fi

info "about to erase $DISK — install.sh will ask you to type YES"
lsblk "$DISK" | sed 's/^/    /'

export DISK
export INSTALL_HOSTNAME="${INSTALL_HOSTNAME:-nixos}"
export INSTALL_USERNAME="${INSTALL_USERNAME:-nixuser}"
export INSTALL_DESKTOP="${INSTALL_DESKTOP:-}"
export SWAP_SIZE="${SWAP_SIZE:-4G}"
export TIMEZONE="${TIMEZONE:-UTC}"
export CHEZMOI_REPO="${CHEZMOI_REPO:-}"
export CHEZMOI_REV="${CHEZMOI_REV:-}"
export FLAKE_INPUTS="${FLAKE_INPUTS:-lock}"
export FLAKE_ATTR="${FLAKE_ATTR:-nixos}"

if [[ -t 0 ]]; then
  exec "$FLAKE_ROOT/scripts/install.sh"
fi
# stdin is the curl pipe that bash is still reading this script from, so only
# install.sh gets the terminal
{ : </dev/tty; } 2>/dev/null || die "no terminal for the prompts (run from a console)"
exec "$FLAKE_ROOT/scripts/install.sh" </dev/tty
