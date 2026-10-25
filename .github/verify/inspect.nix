# Facts about the evaluated system, printed by the verify workflow.
# nix eval --impure --json --expr 'import ./.github/verify/inspect.nix { flake = builtins.getFlake "path:${PWD}"; }'
{ flake }:

let
  c = flake.nixosConfigurations.nixos.config;
  lzb = c.boot.lanzaboote;
  units = c.systemd.services;
in
{
  toplevel = c.system.build.toplevel.drvPath;
  systemdBoot = c.boot.loader.systemd-boot.enable;
  configurationLimit = c.boot.loader.systemd-boot.configurationLimit;
  cryptroot = {
    inherit (c.boot.initrd.luks.devices.cryptroot) device crypttabExtraOpts;
  };
  secureBoot = {
    inherit (lzb) enable pkiBundle configurationLimit;
    externalLoader = c.boot.loader.external.enable;
    autoGenerateKeys = lzb.autoGenerateKeys.enable;
    autoEnrollKeys = {
      inherit (lzb.autoEnrollKeys) enable autoReboot includeMicrosoftKeys;
    };
    loaderConf = lzb.settings;
    sbctlConf = c.environment.etc."sbctl/sbctl.conf".source;
    generateKeys = units.generate-sb-keys.unitConfig;
    prepareEnroll = {
      inherit (units.prepare-sb-auto-enroll) after unitConfig;
    };
    keysPersisted = builtins.filter (
      d: d.directory == lzb.pkiBundle
    ) c.environment.persistence."/persist".directories;
    keysMounted = builtins.hasAttr lzb.pkiBundle c.fileSystems;
  };
}
