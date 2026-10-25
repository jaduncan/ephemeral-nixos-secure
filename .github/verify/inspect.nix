# Facts about the evaluated system, printed by the verify workflow.
# nix eval --impure --json --expr 'import ./.github/verify/inspect.nix { flake = builtins.getFlake "path:${PWD}"; }'
{ flake }:

let
  c = flake.nixosConfigurations.nixos.config;
in
{
  toplevel = c.system.build.toplevel.drvPath;
  initrdSystemd = c.boot.initrd.systemd.enable;
  systemdBoot = c.boot.loader.systemd-boot.enable;
  configurationLimit = c.boot.loader.systemd-boot.configurationLimit;
  cryptroot = {
    inherit (c.boot.initrd.luks.devices.cryptroot) device crypttabExtraOpts;
  };
}
