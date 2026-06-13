{
  description = "nixos-configuration for andongni";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Keep claude-code on an independently updatable nixpkgs pin
    nixpkgs-claude-code.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Add the NUR input
    nur.url = "github:nix-community/NUR";
  };

  outputs = { self, nixpkgs, nixpkgs-claude-code, home-manager, nur, ... }:
    let
      system = "x86_64-linux";
      claudeCodePkgs = import nixpkgs-claude-code {
        inherit system;
        config.allowUnfree = true;
      };
      customOverlay = final: prev: {
        kreuzberg-cli = final.callPackage ./pkgs/kreuzberg-cli.nix { };
        claude-code = claudeCodePkgs.claude-code;
      };
    in {
    nixosConfigurations.andongni = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        # Import NUR modules and custom overlay
        { nixpkgs.overlays = [ nur.overlays.default customOverlay ]; }
        ./configuration.nix

        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.users.andongni = import ./home/andongni.nix;
        }
      ];
    };
  };
}
