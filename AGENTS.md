# Repository Guidelines

## Project Structure & Module Organization

This repository is a NixOS flake for the `andongni` host. Entry points are `flake.nix`, `configuration.nix`, and `hardware-configuration.nix`. System modules live under `modules/`: `system/`, `desktop/`, `hardware/`, `services/`, and `programs/`. Home Manager starts at `home/andongni.nix`; user modules are in `home/programs/`, packages in `home/packages/`, and desktop settings in `home/desktop/`. Custom derivations are in `pkgs/`; user accounts are under `users/`. Managed dotfiles and assets are in `dotfiles/` and `assets/`. Notes belong in `docs/`.

## Build, Test, and Development Commands

- `nix flake check --impure`: evaluate the flake and catch Nix errors. This host's Mihomo configuration reads an absolute `/home/...` path, so plain pure evaluation fails.
- `sudo nixos-rebuild dry-build --flake .#andongni --impure`: build the system closure without switching generations.
- `sudo nixos-rebuild switch --flake .#andongni --impure`: apply the configuration to the local host.
- `sudo ./scripts/mihomo-safe-rebuild.sh`: rebuild with rollback protection for Mihomo connectivity changes.
- `sudo ./scripts/mihomo-safe-rebuild.sh cancel`: cancel rollback after a successful rebuild.
- `find . -name '*.nix' -print0 | xargs -0 nixfmt`: format Nix files.

## Rebuild Policy

Always apply configuration changes by running `sudo nixos-rebuild switch --flake .#andongni --impure`.

## Coding Style & Naming Conventions

Use two-space indentation in Nix files. Keep modules focused on one concern and name files by feature, for example `modules/services/keyd.nix` or `home/programs/tmux.nix`. Prefer explicit imports in aggregator files over hidden dynamic loading. Keep comments brief around hardware, network, or host-specific behavior.

## hyprwhspr Packaging

`pkgs/hyprwhspr.nix` should package upstream runtime files that shipped commands depend on, including `bin`, `config`, `lib`, `share`, `scripts`, and `utils`. Expose user-facing upstream launchers with wrappers in `$out/bin`; auxiliary tools such as `meeting-recorder` must not live only under `$out/lib/hyprwhspr/bin`. Copy upstream docs, contrib files, and license material to `$out/share/doc/hyprwhspr`. The local host uses hyprwhspr with the REST backend; do not assume local backends such as `pywhispercpp` work unless their Python dependencies are explicitly added to the Nix environment.

## Testing Guidelines

There is no unit test suite. Run `nix flake check --impure` for all edits; do not use plain `nix flake check` in this repo because the Mihomo module requires impure access to a host-local `/home/...` path. Use `sudo nixos-rebuild dry-build --flake .#andongni --impure` only for risky changes, such as boot, hardware, networking, proxy, service, package, overlay, or broad module/import changes. For small Home Manager program tweaks, a direct `sudo nixos-rebuild switch --flake .#andongni --impure` is sufficient after evaluation. For networking or proxy changes, prefer the Mihomo safe rebuild script.

## Commit & Pull Request Guidelines

Recent history uses short imperative subjects such as `Add 115 Browser launcher` and `Fix tmux copy-mode paging keys`. Follow that style: start with a verb, keep the subject specific, and avoid unrelated changes in one commit. Pull requests should summarize changes, list validation commands, call out host-specific effects, and include screenshots only for UI changes.

After a successful rebuild and final review, make a commit so the working configuration has a matching history entry.

## Security & Configuration Tips

Do not commit secrets, private SSH material, generated result symlinks, or machine-local credentials. Keep sensitive settings manual unless already represented safely in the flake. Be careful with `hardware-configuration.nix`, network modules, boot settings, and service definitions because they affect bootability or connectivity.
