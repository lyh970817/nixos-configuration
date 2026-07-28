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
    inputs@{
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
        cli-proxy-api = final.callPackage ./pkgs/cli-proxy-api.nix { };
        codex = final.callPackage ./pkgs/codex.nix { };
        codex-desktop-isolated = final.callPackage ./pkgs/codex-desktop-isolated.nix {
          codexDesktopPackage = codex-desktop-linux.packages.${system}.codex-desktop;
        };
        kreuzberg-cli = final.callPackage ./pkgs/kreuzberg-cli.nix { };
        digg-pp-cli = final.callPackage ./pkgs/digg-pp-cli.nix { };
        hyprwhspr = final.callPackage ./pkgs/hyprwhspr.nix { };
        pi-coding-agent = final.callPackage ./pkgs/pi-coding-agent.nix { };
        pi-openai-server-compaction = final.callPackage ./pkgs/pi-openai-server-compaction.nix { };
        quicktui = final.callPackage ./pkgs/quicktui.nix { };
        # DECSCUSR cursor-shape support (unmerged upstream PR #1355) — needed on
        # both roles: mosh-server parses the escape, mosh-client renders it.
        mosh = prev.mosh.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [ ./pkgs/patches/mosh-cursor-shape.patch ];
        });
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

      nixosConfigurations.system = nixpkgs.lib.nixosSystem {
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

      # Self-contained offline installer ISO (issue 07): a minimal
      # installation environment that bakes the `system` output's own
      # closure into its store, so `nixos-install` on the target fetches
      # nothing. See docs/portable-nixos-usb-installer-spec.md ("Installer
      # (custom self-contained offline ISO)").
      nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit self;
          targetToplevel = self.nixosConfigurations.system.config.system.build.toplevel;
          # All flake inputs (minus self) so iso.nix can bake their source
          # trees into the ISO for fully offline `nixos-install` evaluation.
          flakeInputs = builtins.removeAttrs inputs [ "self" ];
        };
        modules = [
          {
            nixpkgs.overlays = [
              nur.overlays.default
              customOverlay
            ];
          }
          (
            { modulesPath, ... }:
            {
              imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];
            }
          )
          ./installer/iso.nix
        ];
      };
    };
}
