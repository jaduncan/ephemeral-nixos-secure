{
  description = "Ephemeral NixOS with impermanence, LUKS, btrfs (Plasma / GNOME / niri)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";
    };
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      impermanence,
      disko,
      lanzaboote,
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
          ./desktop.nix
          ./hardware-configuration.nix
          impermanence.nixosModules.impermanence
          lanzaboote.nixosModules.lanzaboote
        ];
      };

      # installer ISO: nix build path:.#iso
      iso = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { flakeSrc = ./.; };
        modules = [ ./iso.nix ];
      };
    in
    {
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;

      packages.x86_64-linux.iso = iso.config.system.build.isoImage;

      nixosConfigurations = {
        nixos = mkSystem;
      }
      // lib.optionalAttrs (settings.hostname != "nixos") {
        ${settings.hostname} = mkSystem;
      };
    };
}
