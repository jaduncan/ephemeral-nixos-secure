# Install

See [README.md](./README.md).

```bash
lsblk -d -o NAME,SIZE,TRAN

curl -fsSL https://raw.githubusercontent.com/the-wittch/ephemeral-nixos/main/scripts/bootstrap.sh \
  | sudo env INSTALL_HOSTNAME=nixvm SWAP_SIZE=4G bash -s -- /dev/vda
```

Use `sudo env VAR=value …` (plain `sudo VAR=value` often drops the vars).  
If it stops after printing the disk, type `YES` then Enter.

Or from a clone: `sudo ./scripts/bootstrap.sh /dev/vda`

Prompts: `YES` → LUKS passphrase → login password. Then reboot (ISO detached).

Rebuilds later need `path:.` so `settings.nix` is visible:

```bash
cd /persist/etc/nixos
sudo nixos-rebuild switch --flake path:.#nixos
```
