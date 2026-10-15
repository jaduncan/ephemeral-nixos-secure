# cp settings.example.nix settings.nix

{ lib, flakeRoot }:

let
  defaults = {
    hostname = "nixos";
    username = "nixuser";
    diskDevice = "/dev/nvme0n1";
    swapSize = "16G";
    timeZone = "UTC";
    chezmoiRepo = "";
    allowUnfree = true;
  };

  examplePath = flakeRoot + "/settings.example.nix";
  settingsPath = flakeRoot + "/settings.nix";

  fromExample = if builtins.pathExists examplePath then import examplePath else { };
  fromSettings = if builtins.pathExists settingsPath then import settingsPath else { };

  merged = defaults // fromExample // fromSettings;
in
assert merged.hostname != "";
assert merged.username != "";
assert merged.diskDevice != "";
assert merged.swapSize != "";
assert merged.timeZone != "";
merged
