{
  description = "Ephemeral NixOS with impermanence, LUKS, btrfs, and Plasma";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    impermanence.url = "github:nix-community/impermanence";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      impermanence,
      disko,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      settings = import ./lib/load-settings.nix {
        inherit lib;
        flakeRoot = ./.;
      };

      mkSystem = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit settings; };
        modules = [
          disko.nixosModules.disko
          ./disko.nix
          ./configuration.nix
          ./hardware-configuration.nix
          impermanence.nixosModules.impermanence
        ];
      };
    in
    {
      nixosConfigurations =
        {
          nixos = mkSystem;
        }
        // lib.optionalAttrs (settings.hostname != "nixos") {
          ${settings.hostname} = mkSystem;
        };
    };
}
