{
  description = "nixos-configuration for andongni";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Add the NUR input
    nur.url = "github:nix-community/NUR";
  };

  outputs = { self, nixpkgs, home-manager, nur, ... }: {
    nixosConfigurations.andongni = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # Import NUR modules so you can access it via pkgs.nur
        { nixpkgs.overlays = [ nur.overlays.default ]; }
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
