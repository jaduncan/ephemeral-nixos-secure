{ config, lib, ... }:

{
  options.ephemeral.unfreePackages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [
      "steam"
      "steam-unwrapped"
    ];
    description = ''
      Unfree packages this system may use, by `lib.getName`. Any other unfree
      package fails the build with the name to add here. Plain strings only;
      reading `pkgs` here would loop, since pkgs is built from this list.
    '';
  };

  config.nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (lib.getName pkg) config.ephemeral.unfreePackages;
}
