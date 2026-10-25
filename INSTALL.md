# Install cheat sheet

Full context: [README](./README.md). Pin values: [`RELEASE`](./RELEASE).

**Pinned TUI** (recommended):

```bash
TAG=v1.5.0
REV=e65fc7230e117a9705eda65adc9e5871c870d57d

git clone --branch "$TAG" --depth 1 https://github.com/the-wittch/ephemeral-nixos.git ~/nix
cd ~/nix
[[ $(git rev-parse HEAD) == "$REV" ]] || { echo "hash mismatch"; exit 1; }
sudo ./scripts/tui.sh
```

**Floating main:**

```bash
git clone https://github.com/the-wittch/ephemeral-nixos.git ~/nix
cd ~/nix && sudo ./scripts/tui.sh
```

**Plain** (whole disk):

```bash
curl -fsSL https://raw.githubusercontent.com/the-wittch/ephemeral-nixos/v1.5.0/scripts/bootstrap.sh \
  | sudo env TAG=v1.5.0 EXPECTED_REV=e65fc7230e117a9705eda65adc9e5871c870d57d SWAP_SIZE=4G \
    bash -s -- /dev/vda
```

Rebuild later:

```bash
cd /persist/etc/nixos
sudo nixos-rebuild switch --flake path:.#nixos
```
