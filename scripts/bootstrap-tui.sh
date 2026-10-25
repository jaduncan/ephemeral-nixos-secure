#!/usr/bin/env bash
# Preferred installer entry (gum TUI). For a plain/no-gum path use bootstrap.sh.
#
#   curl -fsSL https://raw.githubusercontent.com/jaduncan/ephemeral-nixos-secure/main/scripts/bootstrap-tui.sh \
#     -o /tmp/bootstrap-tui.sh && sudo bash /tmp/bootstrap-tui.sh
#
# Needs a real TTY (download+run or clone). Don't pipe into sudo bash.

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

DEFAULT_REPO_URL="https://github.com/jaduncan/ephemeral-nixos-secure.git"

REPO_URL="${REPO_URL:-$DEFAULT_REPO_URL}"
BRANCH="${TAG:-${BRANCH:-main}}"
EXPECTED_REV="${EXPECTED_REV:-}"

# shellcheck source=common.sh
# common.sh may be missing when this file is curl'd alone; clone brings it.
_SRC=${BASH_SOURCE[0]:-}
if [[ -n $_SRC && -f $_SRC && $_SRC != /dev/fd/* && -f $(dirname "$_SRC")/common.sh ]]; then
  # shellcheck source=common.sh
  source "$(dirname "$_SRC")/common.sh"
fi

[[ $EUID -eq 0 ]] || die "need root (sudo bash …/bootstrap-tui.sh)"

if [[ ! -t 0 || ! -t 1 ]]; then
  die "no TTY — download the script and run it, or use bootstrap.sh as a fallback"
fi

[[ -d /sys/firmware/efi ]] \
  || die "UEFI required (enable OVMF/UEFI in the VM/firmware)"

export NIX_CONFIG="${NIX_CONFIG-}
experimental-features = nix-command flakes
http2 = false
download-attempts = 5
connect-timeout = 10
"

FLAKE_ROOT=""
src=${BASH_SOURCE[0]:-}
if [[ -n $src && -f $src && $src != /dev/fd/* ]]; then
  src_dir=$(cd "$(dirname "$src")" && pwd)
  if [[ -f $src_dir/../flake.nix ]]; then
    FLAKE_ROOT=$(cd "$src_dir/.." && pwd)
    info "local flake: $FLAKE_ROOT"
  fi
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

[[ -f $FLAKE_ROOT/scripts/tui.sh ]] || die "tui.sh missing in clone"
[[ -f $FLAKE_ROOT/scripts/install.sh ]] || die "install.sh missing in clone"
[[ -f $FLAKE_ROOT/scripts/common.sh ]] || die "common.sh missing in clone"
[[ -f $FLAKE_ROOT/flake.nix ]] || die "flake.nix missing in clone"
chmod +x "$FLAKE_ROOT/scripts/tui.sh" "$FLAKE_ROOT/scripts/install.sh"

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

# Optional: pre-set DISK / INSTALL_* via env; tui prompts for anything missing
DISK="${DISK:-${1:-}}"
if [[ -n $DISK ]]; then
  [[ -b $DISK ]] || die "not a block device: $DISK (omit arg to pick in the TUI)"
fi

export DISK
export INSTALL_HOSTNAME="${INSTALL_HOSTNAME:-}"
export INSTALL_USERNAME="${INSTALL_USERNAME:-}"
export INSTALL_DESKTOP="${INSTALL_DESKTOP:-}"
export SWAP_SIZE="${SWAP_SIZE:-}"
export TIMEZONE="${TIMEZONE:-}"
export CHEZMOI_REPO="${CHEZMOI_REPO:-}"
export CHEZMOI_REV="${CHEZMOI_REV:-}"
export FLAKE_INPUTS="${FLAKE_INPUTS:-}"
export FLAKE_ATTR="${FLAKE_ATTR:-nixos}"

exec "$FLAKE_ROOT/scripts/tui.sh"
