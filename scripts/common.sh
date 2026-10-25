# shellcheck shell=bash
# shared by install.sh / tui.sh / bootstrap.sh — source only, do not execute

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

# Nix double-quoted string escape
nix_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//\$/\\$}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

validate_hostname() {
  [[ $1 =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] \
    || die "invalid hostname: $1 (letters/digits/hyphen)"
}

validate_username() {
  [[ $1 =~ ^[a-z_][a-z0-9_-]*$ && ${#1} -le 32 ]] \
    || die "invalid username: $1 (use [a-z_][a-z0-9_-]*, max 32)"
}

validate_swap() {
  [[ $1 =~ ^[0-9]+[KMGT]?$ ]] || die "invalid swap size: $1 (e.g. 4G, 8192M)"
}

validate_timezone() {
  [[ $1 =~ ^[A-Za-z0-9_/+-]+$ ]] || die "invalid timezone: $1"
}

validate_desktop() {
  case $1 in
    plasma | gnome | niri) ;;
    *) die "desktop must be plasma, gnome, or niri (got: $1)" ;;
  esac
}

validate_chezmoi() {
  local url=$1
  [[ -z $url ]] && return 0
  case $url in
    https://* | ssh://* | git@*) ;;
    *) die "chezmoi repo must start with https://, ssh://, or git@" ;;
  esac
  [[ $url != *$'\n'* && $url != *$'\r'* && $url != *" "* ]] \
    || die "chezmoi repo must be a single token"
}

validate_chezmoi_rev() {
  [[ $1 =~ ^[0-9a-fA-F]{40}$ ]] \
    || die "chezmoi commit must be the full 40-character hash"
}

validate_disk() {
  local d=$1
  [[ -b $d ]] || die "not a block device: $d"
  # reject partitions: …pN, sda1 — allow nvme0n1 / mmcblk0 whole disks
  if [[ $d =~ p[0-9]+$ ]]; then
    die "looks like a partition: $d (use the whole disk, e.g. /dev/nvme0n1)"
  fi
  if [[ $d =~ [0-9]+$ && ! $d =~ nvme[0-9]+n[0-9]+$ && ! $d =~ mmcblk[0-9]+$ && ! $d =~ loop[0-9]+$ ]]; then
    die "looks like a partition: $d (use the whole disk, e.g. /dev/vda)"
  fi
}

validate_allow_unfree() {
  case $1 in
    true | false) ;;
    *) die "allowUnfree must be true or false (got: $1)" ;;
  esac
}

# lock = use flake.lock as-is (create if missing)
# update = nix flake update (newest inputs)
validate_flake_inputs() {
  case $1 in
    lock | update) ;;
    *) die "FLAKE_INPUTS must be lock or update (got: $1)" ;;
  esac
}

validate_flake_attr() {
  [[ $1 =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]] \
    || die "invalid FLAKE_ATTR: $1"
}

require_uefi() {
  [[ -d /sys/firmware/efi ]] \
    || die "UEFI required (this flake uses systemd-boot). Enable OVMF/UEFI in the VM/firmware."
}
