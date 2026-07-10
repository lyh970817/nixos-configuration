# Repository Guidelines

## Project Structure & Module Organization

This repository is a NixOS flake for the `andongni` host. Entry points are `flake.nix`, `configuration.nix`, and `hardware-configuration.nix`. System modules live under `modules/`: `system/`, `desktop/`, `hardware/`, `services/`, and `programs/`. Home Manager starts at `home/andongni.nix`; user modules are in `home/programs/`, packages in `home/packages/`, and desktop settings in `home/desktop/`. Custom derivations are in `pkgs/`; user accounts are under `users/`. Managed dotfiles and assets are in `dotfiles/` and `assets/`. Notes belong in `docs/`.

## Build, Test, and Development Commands

- `sudo nixos-rebuild switch --flake .#andongni --impure`: apply the configuration to the local host.
- `find . -name '*.nix' -print0 | xargs -0 nixfmt`: format Nix files.

## Rebuild Policy

For configuration changes, do not run standalone verification commands before rebuilding. Stage and commit the scoped change first so the configured pre-commit hooks run verification, then apply the committed configuration with `sudo nixos-rebuild switch --flake .#andongni --impure`.

For visual changes, apply the `visual-verification` skill automatically. Treat
the mode active at task start as the entire change scope; change or inspect the
other mode only when the user explicitly requests it. Before committing, a
visual preview may use reliably reversible runtime overrides or isolated
temporary configs. It must not run an uncommitted Home Manager activation or
NixOS rebuild. Commit and rebuild the selected result, then visually inspect the
installed result through `codex-screen`.

## Coding Style & Naming Conventions

Use two-space indentation in Nix files. Keep modules focused on one concern and name files by feature, for example `modules/services/keyd.nix` or `home/programs/tmux.nix`. Prefer explicit imports in aggregator files over hidden dynamic loading. Keep comments brief around hardware, network, or host-specific behavior.

## hyprwhspr Packaging

`pkgs/hyprwhspr.nix` should package upstream runtime files that shipped commands depend on, including `bin`, `config`, `lib`, `share`, `scripts`, and `utils`. Expose user-facing upstream launchers with wrappers in `$out/bin`; auxiliary tools such as `meeting-recorder` must not live only under `$out/lib/hyprwhspr/bin`. Copy upstream docs, contrib files, and license material to `$out/share/doc/hyprwhspr`. The local host uses hyprwhspr with the REST backend; do not assume local backends such as `pywhispercpp` work unless their Python dependencies are explicitly added to the Nix environment.

## Commit & Pull Request Guidelines

Recent history uses short imperative subjects such as `Add 115 Browser launcher` and `Fix tmux copy-mode paging keys`. Follow that style: start with a verb, keep the subject specific, and avoid unrelated changes in one commit. Pull requests should summarize changes, list validation commands, call out host-specific effects, and include screenshots only for UI changes.

Commit configuration changes before rebuilding. Treat the pre-commit hooks as the verification gate before `sudo nixos-rebuild switch --flake .#andongni --impure`; if the rebuild fails, make a follow-up fix commit and rebuild again.

## Security & Configuration Tips

Do not commit secrets, private SSH material, generated result symlinks, or machine-local credentials. Keep sensitive settings manual unless already represented safely in the flake. Be careful with `hardware-configuration.nix`, network modules, boot settings, and service definitions because they affect bootability or connectivity.
