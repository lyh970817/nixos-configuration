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

    # Official Anthropic .deb repackaged for Nix, with Cowork's KVM-backed
    # VM stack (qemu_kvm, OVMF, virtiofsd) bundled into the FHS variant.
    claude-desktop-debian = {
      url = "github:aaddrick/claude-desktop-debian";
    };

    herdr = {
      url = "git+https://github.com/ogulcancelik/herdr.git?ref=refs/tags/v0.8.0";
      inputs.nixpkgs.follows = "nixpkgs";
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
      claude-desktop-debian,
      herdr,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      customOverlay =
        final: prev:
        let
          firstmateTools = final.callPackage ./pkgs/firstmate-tools.nix { };
        in
        {
          "115browser" = final.callPackage ./pkgs/115browser.nix { };
          claude-code = final.callPackage ./pkgs/claude-code.nix { };
          claude-science = final.callPackage ./pkgs/claude-science.nix { };
          cli-proxy-api = final.callPackage ./pkgs/cli-proxy-api.nix { };
          codex = final.callPackage ./pkgs/codex.nix { };
          codexbar = final.callPackage ./pkgs/codexbar.nix { };
          # Desktop needs a current, unmodified CLI of its own. The terminal
          # package above disables Apps, but Desktop's CODEX_CLI_PATH must not.
          codex-desktop-cli = final.callPackage ./pkgs/codex.nix {
            disableApps = false;
          };
          codex-desktop-isolated = final.callPackage ./pkgs/codex-desktop-isolated.nix {
            codexDesktopPackage = codex-desktop-linux.packages.${system}.codex-desktop;
          };
          kreuzberg-cli = final.callPackage ./pkgs/kreuzberg-cli.nix { };
          matrix-icons = final.callPackage ./pkgs/matrix-icons.nix { };
          digg-pp-cli = final.callPackage ./pkgs/digg-pp-cli.nix { };
          # Upstream flake ships the package directly; take it from the pinned input.
          herdr = herdr.packages.${system}.default;
          hyprwhspr = final.callPackage ./pkgs/hyprwhspr.nix { };
          oh-my-pi = final.callPackage ./pkgs/oh-my-pi.nix { };
          pi-coding-agent = final.callPackage ./pkgs/pi-coding-agent.nix { };
          pi-openai-server-compaction = final.callPackage ./pkgs/pi-openai-server-compaction.nix { };
          pi-web-access = final.callPackage ./pkgs/pi-web-access.nix { };
          quicktui = final.callPackage ./pkgs/quicktui.nix { };
          treehouse = firstmateTools.treehouse;
          "no-mistakes" = firstmateTools.no-mistakes;
          gh-axi = firstmateTools.gh-axi;
          chrome-devtools-axi = firstmateTools.chrome-devtools-axi;
          lavish-axi = firstmateTools.lavish-axi;
          tasks-axi = firstmateTools.tasks-axi;
          quota-axi = firstmateTools.quota-axi;
          zeno-zsh = final.callPackage ./pkgs/zeno-zsh.nix { };
          # DECSCUSR cursor-shape support (unmerged upstream PR #1355) — needed on
          # both roles: mosh-server parses the escape, mosh-client renders it.
          mosh = prev.mosh.overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [ ./pkgs/patches/mosh-cursor-shape.patch ];
          });
        };
      # Deliberately thin. `rebuild` is the verification gate: a full evaluation
      # and build already catches every syntax, type, missing-attr, and build
      # error, so re-checking any of that here would only add latency to every
      # commit. These hooks cover the gap -- what a rebuild structurally cannot
      # see. Keep them all parse-or-scan only; nothing that evaluates the flake.
      preCommitCheck = pre-commit-hooks.lib.${system}.run {
        src = ./.;
        # Formatting drift is invisible to a build.
        hooks.nixfmt.enable = true;
        # Home Manager installs these as opaque bytes, so a syntax error here
        # rebuilds perfectly clean and only surfaces when the tool next starts.
        hooks.check-toml.enable = true;
        hooks.check-json.enable = true;
        # Neither of these ever reaches a build, and the second is unrecoverable
        # once it lands in history.
        hooks.check-merge-conflicts.enable = true;
        hooks.detect-private-keys.enable = true;
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
              claude-desktop-debian.overlays.default
              customOverlay
            ];
          }
          ./configuration.nix

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            # home/programs/pre-commit.nix installs the generated hooks at
            # activation, so it needs the same check this flake's devShell uses.
            home-manager.extraSpecialArgs = { inherit preCommitCheck; };
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
