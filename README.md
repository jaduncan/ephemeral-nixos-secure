# EphemeralOS

[![CI](https://github.com/the-wittch/ephemeral-nixos/actions/workflows/ci.yml/badge.svg)](https://github.com/the-wittch/ephemeral-nixos/actions/workflows/ci.yml)

NixOS with an encrypted btrfs disk, root rolled back to blank every boot, and `/home` (plus a few system paths) kept on `/persist`. Desktop is Plasma, GNOME, or niri+Noctalia — pick at install.

```
disk → ESP (/boot)
     → LUKS → btrfs { root, root-blank, nix, persist, log, swap }
```

Machine stuff goes in gitignored `settings.nix`. Passwords live in `/persist/passwords/`, not in the flake.

## Install

UEFI, network up on the graphical ISO.

### Pinned install (recommended)

Use a [release tag](https://github.com/the-wittch/ephemeral-nixos/releases) and check the commit hash. Values live in [`RELEASE`](./RELEASE) on that tag:

```bash
TAG=v1.0.0
REV=d4b66a9f250bf5b220d275b6ecb7762d2d8fc722   # must match RELEASE / the GitHub release

git clone --branch "$TAG" --depth 1 https://github.com/the-wittch/ephemeral-nixos.git ~/nix
cd ~/nix
[[ $(git rev-parse HEAD) == "$REV" ]] || { echo "hash mismatch"; exit 1; }
sudo ./scripts/tui.sh
```

Same pin via bootstrap (no interactive clone):

```bash
curl -fsSL https://raw.githubusercontent.com/the-wittch/ephemeral-nixos/v1.0.0/scripts/bootstrap-tui.sh \
  -o /tmp/bootstrap-tui.sh
sudo env TAG=v1.0.0 EXPECTED_REV=d4b66a9f250bf5b220d275b6ecb7762d2d8fc722 \
  bash /tmp/bootstrap-tui.sh
```

Copy the tag and commit from the latest [GitHub release](https://github.com/the-wittch/ephemeral-nixos/releases) (or from [`RELEASE`](./RELEASE) on that tag) if these examples are stale.

### Floating `main` (dev)

```bash
git clone https://github.com/the-wittch/ephemeral-nixos.git ~/nix
cd ~/nix
sudo ./scripts/tui.sh
```

Plain / no gum:

```bash
curl -fsSL https://raw.githubusercontent.com/the-wittch/ephemeral-nixos/main/scripts/bootstrap.sh \
  | sudo env SWAP_SIZE=4G bash -s -- /dev/vda
```

`sudo env VAR=…` matters; bare `sudo VAR=…` often drops the vars.

You'll set a LUKS passphrase and a login password. Then detach the ISO and reboot.

**VMs:** UEFI (Secure Boot off), VirtIO disk (`/dev/vda`), ~64G disk / 8G RAM is enough. Plymouth can look weird on virtual GPUs; unlock still works.

## After install

Config is at `/persist/etc/nixos`. Always rebuild with `path:.` so gitignored files are visible:

```bash
cd /persist/etc/nixos
sudo nixos-rebuild switch --flake path:.#nixos
```

Sanity check: `sudo touch /ephemeral-test`, drop a file in `~`, reboot. Root file should vanish; home file should stay.

### settings.nix

```nix
{
  hostname = "nixos";
  username = "nixuser";
  diskDevice = "/dev/nvme0n1"; # whole disk, not a partition
  swapSize = "16G";
  timeZone = "UTC";
  desktop = "plasma"; # plasma | gnome | niri
  chezmoiRepo = "";   # optional https://… dotfiles
  allowUnfree = true;
}
```

### Forks and private flakes

Install leaves the flake at `/persist/etc/nixos`. You can keep using this repo as-is and only edit `settings.nix`, or treat that directory as your own flake: fork this project, push to a private remote, and commit machine-specific modules there (DNS, Steam, extra imports, whatever). The public tree is meant to stay a small template; how you split files afterward is up to you.

Rebuilds are the same either way — still `path:.#nixos` so gitignored files are included.

## Repo map

| path | what |
|------|------|
| `flake.nix` | inputs + NixOS configs |
| `disko.nix` | partitions / LUKS / btrfs |
| `configuration.nix` | system |
| `desktop.nix` | Plasma / GNOME / niri |
| `settings.example.nix` | template → `settings.nix` |
| `scripts/tui.sh` | gum installer |
| `scripts/bootstrap.sh` | curl / no-gum installer |
| `scripts/install.sh` | actual disko + nixos-install |

## Gotchas

- **Changing your login password:** `passwd` won't survive reboot (`mutableUsers = false`; hash lives on `/persist`). Do this instead:

  ```bash
  mkpasswd -m sha-512                    # type new password twice; prints a hash
  sudo tee /persist/passwords/$USER      # paste the hash, then Ctrl-D
  sudo chmod 600 /persist/passwords/$USER
  ```

  Next login (or rebuild) uses the new hash. Install already created this file once.

- Hibernation is off on purpose (btrfs swapfile + LUKS). Suspend is fine.
- `/boot` is unencrypted. Bootloader editor is disabled.
- SSH is installed but port 22 is firewalled shut. Keys under `/persist/etc/ssh`.
- `flake.lock` pins nixpkgs/disko/impermanence. The TUI asks whether to keep those pins or run `nix flake update` for newest. Plain install defaults to the lock (`FLAKE_INPUTS=update` to refresh).

## Troubleshooting

| symptom | try |
|---------|-----|
| text LUKS prompt | `initrd.systemd` + plymouth (already on here) |
| black screen at unlock | uncomment `plymouth.use-simpledrm` or add early KMS |
| settings ignored | `path:.#nixos`, not `.#nixos` |
| home/wifi reset every boot | `/persist` not `neededForBoot` |
| can't log in | missing `/persist/passwords/<user>` |
| "Booting from Hard Disk…" forever | UEFI VM + Secure Boot off; ISO detached |
| gum segfault / no disks | `git pull` and retry, or use `bootstrap.sh` |
| getcwd / cannot get current path | pull latest install.sh; or `cd / && sudo nixos-install --no-root-passwd --flake path:/mnt/persist/etc/nixos#nixos` |

## Manual install

```bash
cp settings.example.nix settings.nix
cp hardware-configuration.example.nix hardware-configuration.nix
# edit settings

sudo nix run github:nix-community/disko -- --flake path:.#nixos --mode destroy,format,mount
sudo btrfs subvolume list /mnt   # expect root-blank

sudo mkdir -p /mnt/persist/passwords /mnt/persist/etc/ssh /mnt/persist/etc/nixos
sudo chmod 700 /mnt/persist/passwords
mkpasswd -m sha-512 | sudo tee /mnt/persist/passwords/nixuser
sudo chmod 600 /mnt/persist/passwords/nixuser
sudo cp -a . /mnt/persist/etc/nixos/

sudo nixos-install --no-root-passwd --flake path:/mnt/persist/etc/nixos#nixos
```

[Disko](https://github.com/nix-community/disko) · [impermanence](https://github.com/nix-community/impermanence)
