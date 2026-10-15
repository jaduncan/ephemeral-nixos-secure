# cp settings.example.nix settings.nix
# rebuild with: sudo nixos-rebuild switch --flake path:.#nixos

{
  hostname = "nixos";
  username = "nixuser";

  # whole disk, not a partition
  diskDevice = "/dev/nvme0n1";

  swapSize = "16G";
  timeZone = "UTC";

  # e.g. "https://github.com/you/dotfiles.git"
  chezmoiRepo = "";

  allowUnfree = true;
}
