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

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    codex-desktop-linux = {
      url = "github:ilysenko/codex-desktop-linux";
    };

  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nur,
      pre-commit-hooks,
      codex-desktop-linux,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      customOverlay = final: prev: {
        "115browser" = final.callPackage ./pkgs/115browser.nix { };
        claude-code = final.callPackage ./pkgs/claude-code.nix { };
        kreuzberg-cli = final.callPackage ./pkgs/kreuzberg-cli.nix { };
        digg-pp-cli = final.callPackage ./pkgs/digg-pp-cli.nix { };
        hyprwhspr = final.callPackage ./pkgs/hyprwhspr.nix { };
      };
      preCommitCheck = pre-commit-hooks.lib.${system}.run {
        src = ./.;
        hooks.nixfmt.enable = true;
        hooks.nix-gc = {
          enable = true;
          name = "nix garbage collect";
          entry = "sh -c 'sudo -n nix-collect-garbage --delete-older-than 3d'";
          language = "system";
          pass_filenames = false;
          always_run = true;
          stages = [ "pre-push" ];
        };
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
            home-manager.users.andongni = {
              imports = [
                codex-desktop-linux.homeManagerModules.default
                ./home/andongni.nix
              ];
            };
          }
        ];
      };
    };
}
