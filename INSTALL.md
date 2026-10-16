# Install

See [README.md](./README.md).

**TUI (preferred)** — needs a TTY:

```bash
curl -fsSL https://raw.githubusercontent.com/the-wittch/ephemeral-nixos/main/scripts/bootstrap-tui.sh \
  -o /tmp/bootstrap-tui.sh
sudo bash /tmp/bootstrap-tui.sh
```

**Plain fallback:**

```bash
curl -fsSL https://raw.githubusercontent.com/the-wittch/ephemeral-nixos/main/scripts/bootstrap.sh \
  | sudo env INSTALL_HOSTNAME=nixvm SWAP_SIZE=4G bash -s -- /dev/vda
```

Use `sudo env VAR=value …` (plain `sudo VAR=value` often drops the vars).

Or from a clone: `sudo ./scripts/tui.sh` / `sudo ./scripts/bootstrap.sh /dev/vda`

Rebuilds later need `path:.` so `settings.nix` is visible:

```bash
cd /persist/etc/nixos
sudo nixos-rebuild switch --flake path:.#nixos
```
