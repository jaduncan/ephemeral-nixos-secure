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

Clone and run the TUI (needs a real terminal; don't pipe this into sudo):

```bash
git clone https://github.com/the-wittch/ephemeral-nixos.git ~/nix
cd ~/nix
sudo ./scripts/tui.sh
```

No clone / no gum — plain script, pass the whole disk:

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

- `passwd` doesn't stick across reboot — edit `/persist/passwords/$USER` (sha-512 hash) or re-run `mkpasswd`.
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
