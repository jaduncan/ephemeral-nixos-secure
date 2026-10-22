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

  examplePath = flakeRoot + "/settings.example.nix";
  settingsPath = flakeRoot + "/settings.nix";

  fromExample = if builtins.pathExists examplePath then import examplePath else { };
  fromSettings = if builtins.pathExists settingsPath then import settingsPath else { };

  merged = defaults // fromExample // fromSettings;
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
