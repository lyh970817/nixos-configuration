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
      palette = (import ./home/palettes.nix).active;
      customOverlay = final: prev: {
        "115browser" = final.callPackage ./pkgs/115browser.nix { };
        # Bibata Original rebuilt in custom colours, in the three variants the
        # design document proposes. All three install side by side under
        # distinct theme names so they can be compared live with
        # `hyprctl setcursor <name> 22` plus a freshly spawned client; only the
        # first is wired into dark mode (home/desktop/theming.nix).
        #
        # The accent is always bound to a palette rung rather than to a literal,
        # so a phosphor retune carries the cursors with it. The body and outline
        # are not rungs of any ladder -- they exist to keep the pointer looking
        # like a pointer -- so they stay literal, and the utilitarian pair stays
        # in the package's own defaults.
        #
        # 1. Utilitarian: grey body, near-black outline, green only in the
        #    loading disc. The active choice.
        bibata-vt220-cursors = final.callPackage ./pkgs/bibata-vt220-cursors.nix {
          accentColor = "#${palette.foreground}";
        };
        # 2. Darker: the inverse -- near-black body, pale grey-green outline.
        #    Reads as an outline-only pointer on the dark background, where the
        #    #18201A body sits at about 1.2:1 against it; the fill only appears
        #    over light surfaces.
        bibata-vt220-cursors-darker = final.callPackage ./pkgs/bibata-vt220-cursors.nix {
          themeName = "Bibata-Original-VT220-Darker";
          themeComment = "Dark-bodied sharp edge Bibata XCursors with a pale outline";
          baseColor = "#18201A";
          outlineColor = "#96A298";
          accentColor = "#${palette.foreground}";
        };
        # 3. Compromise: muted green-grey body for slightly more thematic
        #    integration, and the brighter rung for the accent so the loading
        #    disc still separates from the body.
        bibata-vt220-cursors-muted = final.callPackage ./pkgs/bibata-vt220-cursors.nix {
          themeName = "Bibata-Original-VT220-Muted";
          themeComment = "Muted green-grey sharp edge Bibata XCursors with phosphor-green detail";
          baseColor = "#69756C";
          outlineColor = "#0A100C";
          accentColor = "#${palette.bright}";
        };
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
        xberg-cli = final.callPackage ./pkgs/xberg-cli.nix { };
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
        screen-shader-controller = final.callPackage ./pkgs/screen-shader-controller.nix { };
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
