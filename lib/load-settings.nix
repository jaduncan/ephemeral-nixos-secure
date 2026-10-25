# cp settings.example.nix settings.nix

{ lib, flakeRoot }:

let
  defaults = {
    hostname = "nixos";
    username = "nixuser";
    diskDevice = "/dev/nvme0n1";
    swapSize = "16G";
    timeZone = "UTC";
    desktop = "plasma"; # plasma | gnome | niri
    allowUnfree = true;
  };

  settingsPath = flakeRoot + "/settings.nix";

  fromSettings =
    if builtins.pathExists settingsPath then
      import settingsPath
    else
      throw ''
        settings.nix is not in this flake.
        Copy settings.example.nix to settings.nix, then rebuild the installed tree:
          sudo nixos-rebuild switch --flake path:/persist/etc/nixos#nixos
      '';

  merged =
    if !(fromSettings ? username) || fromSettings.username == "" then
      throw "settings.nix must set username"
    else
      defaults // fromSettings;
  merged' =
    if (merged.chezmoiRepo or "") != "" then
      throw ''
        Don't put chezmoiRepo in settings.
        chezmoi: /persist/etc/chezmoi-repo as "<git-url> <commit>".
      ''
    else
      merged;
in
assert merged'.hostname != "";
assert merged'.username != "";
assert merged'.diskDevice != "";
assert merged'.swapSize != "";
assert merged'.timeZone != "";
assert builtins.elem merged'.desktop [
  "plasma"
  "gnome"
  "niri"
];
removeAttrs merged' [ "chezmoiRepo" ]
