# Install cheat sheet

Full context: [README](./README.md).

**TUI** (clone first — needs a TTY):

```bash
git clone https://github.com/the-wittch/ephemeral-nixos.git ~/nix
cd ~/nix && sudo ./scripts/tui.sh
```

**Plain** (pass the whole disk):

```bash
curl -fsSL https://raw.githubusercontent.com/the-wittch/ephemeral-nixos/main/scripts/bootstrap.sh \
  | sudo env SWAP_SIZE=4G bash -s -- /dev/vda
```

Use `sudo env VAR=value …`. Detach ISO after it finishes, reboot, unlock LUKS.

Rebuild later:

```bash
cd /persist/etc/nixos
sudo nixos-rebuild switch --flake path:.#nixos
```
