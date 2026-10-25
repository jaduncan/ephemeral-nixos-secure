# cp settings.example.json settings.json

{ lib, flakeRoot }:

let
  readData = import ./read-data.nix { inherit lib; };

  defaults = {
    hostname = "nixos";
    username = "nixuser";
    diskDevice = "/dev/nvme0n1";
    swapSize = "16G";
    timeZone = "UTC";
    desktop = "plasma"; # plasma | gnome | niri
  };

  fromSettings = readData (flakeRoot + "/settings") (throw ''
    settings.json is not in this flake.
    Copy settings.example.json to settings.json, then rebuild the installed tree:
      sudo nixos-rebuild switch --flake path:/persist/etc/nixos#nixos
  '');

  merged =
    if !(fromSettings ? username) || fromSettings.username == "" then
      throw "settings must set username"
    else
      defaults // fromSettings;
  merged' =
    if (merged.chezmoiRepo or "") != "" then
      throw ''
        Don't put chezmoiRepo in settings.
        chezmoi: /persist/etc/chezmoi-repo as "<git-url> <commit>".
      ''
    else
      lib.warnIf (merged ? allowUnfree)
        "settings.allowUnfree is no longer used. Unfree packages are listed in ephemeral.unfreePackages."
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
removeAttrs merged' [
  "chezmoiRepo"
  "allowUnfree"
]
