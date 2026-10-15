#!/usr/bin/env bash
# curl -fsSL https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/scripts/bootstrap.sh \
#   | sudo bash -s -- /dev/vda
#
# set DEFAULT_REPO_URL below, or pass REPO_URL=...

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

DEFAULT_REPO_URL="https://github.com/YOUR_USER/YOUR_REPO.git"

REPO_URL="${REPO_URL:-$DEFAULT_REPO_URL}"
BRANCH="${BRANCH:-main}"

[[ $EUID -eq 0 ]] || die "need root"

DISK="${1:-${DISK:-}}"
[[ -n $DISK ]] || die "usage: $0 /dev/vda"
[[ -b $DISK ]] || die "not a block device: $DISK"

FLAKE_ROOT=""
src=${BASH_SOURCE[0]:-}
if [[ -n $src && -f $src ]]; then
  src_dir=$(cd "$(dirname "$src")" && pwd)
  if [[ -f $src_dir/../flake.nix ]]; then
    FLAKE_ROOT=$(cd "$src_dir/.." && pwd)
    info "local flake: $FLAKE_ROOT"
  fi
fi

if [[ -z $FLAKE_ROOT ]]; then
  if [[ $REPO_URL == *YOUR_USER* || $REPO_URL == *YOUR_REPO* ]]; then
    die "set DEFAULT_REPO_URL or REPO_URL"
  fi
  command -v git >/dev/null || die "git not found"

  FLAKE_ROOT=$(mktemp -d /tmp/nixos-flake.XXXXXX)
  info "clone $REPO_URL → $FLAKE_ROOT"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$FLAKE_ROOT"
fi

[[ -x $FLAKE_ROOT/scripts/install.sh ]] || chmod +x "$FLAKE_ROOT/scripts/install.sh"
[[ -f $FLAKE_ROOT/flake.nix ]] || die "flake.nix missing"

info "erasing $DISK"
lsblk "$DISK" | sed 's/^/    /'

export DISK
export INSTALL_HOSTNAME="${INSTALL_HOSTNAME:-nixos}"
export INSTALL_USERNAME="${INSTALL_USERNAME:-nixuser}"
export SWAP_SIZE="${SWAP_SIZE:-4G}"
export TIMEZONE="${TIMEZONE:-UTC}"
export CHEZMOI_REPO="${CHEZMOI_REPO:-}"
export ALLOW_UNFREE="${ALLOW_UNFREE:-true}"
export FLAKE_ATTR="${FLAKE_ATTR:-nixos}"

exec "$FLAKE_ROOT/scripts/install.sh"
