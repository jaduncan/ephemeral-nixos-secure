# Machine files next to the flake are JSON, so scripts can edit them with jq
# and nothing generated is ever evaluated as code. A .nix file of the same
# name still loads, with a warning that says how to convert it.
{ lib }:

base: default:
let
  name = baseNameOf (toString base);
  json = base + ".json";
  legacy = base + ".nix";
in
if builtins.pathExists json then
  builtins.fromJSON (builtins.readFile json)
else if builtins.pathExists legacy then
  lib.warn (
    "${name}.nix is deprecated. Convert it once, then delete the .nix file:\n"
    + "  nix eval --json --file ${name}.nix | nix run nixpkgs#jq -- . > ${name}.json"
  ) (import legacy)
else
  default
