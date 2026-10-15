# Install

See [README.md](./README.md).

```bash
lsblk -d -o NAME,SIZE,TRAN

curl -fsSL https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/scripts/bootstrap.sh \
  | sudo bash -s -- /dev/vda
```

Or from a clone: `sudo ./scripts/bootstrap.sh /dev/vda`

Prompts: `YES` → LUKS passphrase → login password. Then reboot (ISO detached).

Rebuilds later need `path:.` so `settings.nix` is visible:

```bash
cd /persist/etc/nixos
sudo nixos-rebuild switch --flake path:.#nixos
```
