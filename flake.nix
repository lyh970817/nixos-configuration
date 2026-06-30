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

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-claude-code,
      home-manager,
      nur,
      pre-commit-hooks,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      claudeCodePkgs = import nixpkgs-claude-code {
        inherit system;
        config.allowUnfree = true;
      };
      customOverlay = final: prev: {
        "115browser" = final.callPackage ./pkgs/115browser.nix { };
        kreuzberg-cli = final.callPackage ./pkgs/kreuzberg-cli.nix { };
        digg-pp-cli = final.callPackage ./pkgs/digg-pp-cli.nix { };
        hyprwhspr = final.callPackage ./pkgs/hyprwhspr.nix { };
        claude-code = claudeCodePkgs.claude-code;
      };
      preCommitCheck = pre-commit-hooks.lib.${system}.run {
        src = ./.;
        hooks.nixfmt.enable = true;
      };
    in
    {
      checks.${system}.pre-commit = preCommitCheck;

      formatter.${system} = pkgs.nixfmt;

      devShells.${system}.default = pkgs.mkShell {
        inherit (preCommitCheck) shellHook;
        packages = with pkgs; [
          nixfmt
          pre-commit
        ];
      };

      nixosConfigurations.andongni = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          # Import NUR modules and custom overlay
          {
            nixpkgs.overlays = [
              nur.overlays.default
              customOverlay
            ];
          }
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
