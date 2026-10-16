#!/usr/bin/env bash
# curl -fsSL https://raw.githubusercontent.com/the-wittch/ephemeral-nixos/main/scripts/bootstrap.sh \
#   | sudo env SWAP_SIZE=4G bash -s -- /dev/vda

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

DEFAULT_REPO_URL="https://github.com/the-wittch/ephemeral-nixos.git"

REPO_URL="${REPO_URL:-$DEFAULT_REPO_URL}"
BRANCH="${BRANCH:-main}"

[[ $EUID -eq 0 ]] || die "need root (use: curl ... | sudo env ... bash -s -- /dev/DISK)"

# Installer ISO often has these off; http2=false avoids stalled cache downloads in VMs
export NIX_CONFIG="${NIX_CONFIG-}
experimental-features = nix-command flakes
http2 = false
download-attempts = 5
connect-timeout = 10
"

DISK="${1:-${DISK:-}}"
[[ -n $DISK ]] || die "usage: bash -s -- /dev/vda"
[[ -b $DISK ]] || die "not a block device: $DISK"

info "REPO_URL=$REPO_URL"
info "BRANCH=$BRANCH"
info "DISK=$DISK"

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
  info "cloning $REPO_URL (branch $BRANCH) → $FLAKE_ROOT"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$FLAKE_ROOT" \
    || die "git clone failed (check URL/branch and network)"
fi

[[ -f $FLAKE_ROOT/scripts/install.sh ]] || die "install.sh missing in clone"
[[ -f $FLAKE_ROOT/flake.nix ]] || die "flake.nix missing in clone"
chmod +x "$FLAKE_ROOT/scripts/install.sh"

info "about to erase $DISK — install.sh will ask you to type YES"
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
