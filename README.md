# EphemeralOS

[![CI](https://github.com/the-wittch/ephemeral-nixos/actions/workflows/ci.yml/badge.svg)](https://github.com/the-wittch/ephemeral-nixos/actions/workflows/ci.yml)

Ephemeral NixOS: LUKS + btrfs via Disko, root wiped each boot (impermanence), Plymouth unlock. Pick Plasma, GNOME, or niri + Noctalia at install.

Persistent bits live under `/persist` (including all of `/home`). Machine-specific stuff goes in gitignored `settings.nix`.

```
disk
├─ ESP → /boot
└─ LUKS → btrfs
   ├─ root / root-blank
   ├─ nix
   ├─ persist
   ├─ log
   └─ swap
```

## Layout

| file | notes |
|------|--------|
| `flake.nix` | nixpkgs, disko, impermanence |
| `disko.nix` | partitions |
| `configuration.nix` | system |
| `desktop.nix` | plasma / gnome / niri+Noctalia |
| `settings.example.nix` | copy → `settings.nix` |
| `hardware-configuration.example.nix` | copy → `hardware-configuration.nix` |
| `scripts/bootstrap-tui.sh` | preferred: gum TUI → install |
| `scripts/bootstrap.sh` | plain fallback (no gum) |
| `scripts/tui.sh` | gum prompts |
| `scripts/install.sh` | disko + nixos-install |

`settings.nix` and `hardware-configuration.nix` are gitignored. Rebuild with `path:.` so the flake can see them:

```bash
sudo nixos-rebuild switch --flake path:.#nixos
```

### settings.nix

```nix
{
  hostname = "nixos";
  username = "nixuser";
  diskDevice = "/dev/nvme0n1"; # whole disk
  swapSize = "16G";
  timeZone = "UTC";
  desktop = "plasma"; # plasma | gnome | niri
  chezmoiRepo = "";
  allowUnfree = true;
}
```

Don't put password hashes in nix — they end up in the store. Install puts them in `/persist/passwords/<user>`.

## Install

Needs UEFI. On the installer ISO, get network working.

### TUI (preferred)

Needs a real TTY (gum). Download then run — don’t pipe into `sudo bash`:

```bash
curl -fsSL https://raw.githubusercontent.com/the-wittch/ephemeral-nixos/main/scripts/bootstrap-tui.sh \
  -o /tmp/bootstrap-tui.sh
sudo bash /tmp/bootstrap-tui.sh
```

Or from a clone: `sudo ./scripts/tui.sh` / `sudo ./scripts/bootstrap-tui.sh`.

Fetches `gum` via nix if needed. Walks disk, desktop, hostname, etc., then runs the same `install.sh` path.

### Plain fallback

```bash
curl -fsSL https://raw.githubusercontent.com/the-wittch/ephemeral-nixos/main/scripts/bootstrap.sh \
  | sudo env INSTALL_HOSTNAME=nixvm SWAP_SIZE=4G bash -s -- /dev/vda
```

Use `sudo env …` so vars reach the script. Prompts for desktop, `YES`, LUKS, login password. Or set `INSTALL_DESKTOP=niri` to skip the menu.

If `main` 404s, try `master` or pass `BRANCH=…`.

Env vars: `INSTALL_HOSTNAME`, `INSTALL_USERNAME`, `INSTALL_DESKTOP`, `SWAP_SIZE`, `TIMEZONE`, `REPO_URL`, `BRANCH`, `CONFIRM=YES`, `DISK`.

VMs: use UEFI/OVMF, VirtIO disk (usually `/dev/vda`), ≥64G disk / 8G RAM. Swap of `4G` is fine. Plymouth may look ugly on virtual GPUs; unlock still works.

After install the flake is at `/persist/etc/nixos`.

```bash
cd /persist/etc/nixos
sudo nixos-rebuild switch --flake path:.#nixos
```

Quick impermanence check: `sudo touch /ephemeral-test`, put a file in `~`, reboot — root file gone, home file stays.

## Manual install

If you don't want the scripts:

```bash
cp settings.example.nix settings.nix
cp hardware-configuration.example.nix hardware-configuration.nix
# edit diskDevice, etc.

sudo nix run github:nix-community/disko -- --flake path:.#nixos --mode destroy,format,mount
sudo btrfs subvolume list /mnt   # need root-blank

sudo mkdir -p /mnt/persist/passwords /mnt/persist/etc/ssh /mnt/persist/etc/nixos
sudo chmod 700 /mnt/persist/passwords
mkpasswd -m sha-512 | sudo tee /mnt/persist/passwords/nixuser
sudo chmod 600 /mnt/persist/passwords/nixuser
sudo cp -a . /mnt/persist/etc/nixos/

sudo nixos-install --flake path:.#nixos
sudo reboot
```

## Notes

- `/persist` and `/var/log` must be `neededForBoot` or bind mounts break in weird ways.
- Rollback only replaces `root`. Don't touch `nix` / `persist` / `log` / `swap` in that script.
- `passwd` alone won't survive reboot; use `/persist/passwords/$USER`.
- Hibernation is off (btrfs swapfile + LUKS is a pain). Suspend is fine.
- `/boot` is unencrypted (normal for UEFI). Boot menu editor is disabled.
- SSH is enabled but port 22 is closed until you open it. Host keys are under `/persist/etc/ssh`.
- `allowDiscards` + fstrim are on for SSDs; turn off if you care about TRIM leakage.
- Generate and commit a `flake.lock` when you can (`nix flake lock`).

## Troubleshooting

| problem | usually |
|---------|---------|
| text LUKS prompt | need `initrd.systemd` + plymouth |
| long black screen at unlock | try `plymouth.use-simpledrm` or early KMS |
| settings ignored | use `path:.#nixos`, not `.#nixos` |
| home/wifi wiped every boot | `/persist` not `neededForBoot` |
| can't log in after reboot | missing `/persist/passwords/...` |
| no flathub | wait for network / `flatpak remotes` |

[Disko](https://github.com/nix-community/disko) · [impermanence](https://github.com/nix-community/impermanence) · [plymouth](https://wiki.nixos.org/wiki/Plymouth)
