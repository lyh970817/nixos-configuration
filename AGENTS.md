# Repository Guidelines

## Project Structure & Module Organization

This repository is a NixOS flake for the `andongni` host. Entry points are `flake.nix`, `configuration.nix`, and `hardware-configuration.nix`. System modules live under `modules/`: `system/`, `desktop/`, `hardware/`, `services/`, and `programs/`. Home Manager starts at `home/andongni.nix`; user modules are in `home/programs/`, packages in `home/packages/`, and desktop settings in `home/desktop/`. Custom derivations are in `pkgs/`; user accounts are under `users/`. Managed dotfiles and assets are in `dotfiles/` and `assets/`. Notes belong in `docs/`.

## Build, Test, and Development Commands

- `rebuild`: apply the configuration to the local host. The alias invokes `sudo nixos-rebuild switch --flake /etc/nixos#system --impure`, so it works from any directory through the stable `/etc/nixos` checkout symlink.
- `sudo nixos-rebuild switch --flake .#system --impure`: apply the configuration directly when already in this checkout.
- `find . -name '*.nix' -print0 | xargs -0 nixfmt`: format Nix files.

## Rebuild Policy

For configuration changes, do not run standalone verification commands before rebuilding. Stage and commit the scoped change first so the configured pre-commit hooks run verification, then apply the committed configuration with `rebuild`.

For visual changes, apply the `visual-verification` skill automatically. Treat
the mode active at task start as the entire change scope; change or inspect the
other mode only when the user explicitly requests it. Before committing, a
visual preview may use reliably reversible runtime overrides or isolated
temporary configs. It must not run an uncommitted Home Manager activation or
NixOS rebuild. Commit and rebuild the selected result, then visually inspect the
installed result through `screen-verify`.

## Mihomo Configuration Acceptance

`mihomo-config.yaml` is intentionally ignored because it may contain sensitive
local configuration. There is no tracked configuration-identity file: never
create or commit `mihomo-config.sha256`. Runtime state at
`/var/lib/mihomo-config/accepted-config.sha256` records the SHA-256 of the exact
active store-backed configuration that the user last accepted.

The ordinary local deployment command is always:

```sh
rebuild
```

A rebuild is not blocked when the Mihomo configuration changes. During
activation it compares the candidate's exact immutable configuration with the
accepted SHA. If they differ, the rebuild output asks the user to wait for the
rebuild command to finish, test the connection and routing, and, only if they
work, run:

```sh
sudo mihomo-config accept
```

The acceptance command resolves the exact active deployed configuration from
the active `mihomo.service` unit. It refuses to write state unless the active
system closure is also the persistent system profile and `mihomo.service` is
active. It then atomically records the active configuration SHA in root-owned
runtime state. It does not rebuild or reactivate the system.

Inspect the current acceptance status with:

```sh
mihomo-config status
```

## Coding Style & Naming Conventions

Use two-space indentation in Nix files. Keep modules focused on one concern and name files by feature, for example `modules/services/keyd.nix` or `home/programs/tmux.nix`. Prefer explicit imports in aggregator files over hidden dynamic loading. Keep comments brief around hardware, network, or host-specific behavior.

## hyprwhspr Packaging

`pkgs/hyprwhspr.nix` should package upstream runtime files that shipped commands depend on, including `bin`, `config`, `lib`, `share`, `scripts`, and `utils`. Expose user-facing upstream launchers with wrappers in `$out/bin`; auxiliary tools such as `meeting-recorder` must not live only under `$out/lib/hyprwhspr/bin`. Copy upstream docs, contrib files, and license material to `$out/share/doc/hyprwhspr`. The local host uses hyprwhspr with the REST backend; do not assume local backends such as `pywhispercpp` work unless their Python dependencies are explicitly added to the Nix environment.

## Commit & Pull Request Guidelines

Recent history uses short imperative subjects such as `Add 115 Browser launcher` and `Fix tmux copy-mode paging keys`. Follow that style: start with a verb, keep the subject specific, and avoid unrelated changes in one commit. Pull requests should summarize changes, list validation commands, call out host-specific effects, and include screenshots only for UI changes.

Commit configuration changes before rebuilding. Treat the pre-commit hooks as the verification gate before `rebuild`; if the rebuild fails, make a follow-up fix commit and rebuild again.

## Security & Configuration Tips

Do not commit secrets, private SSH material, generated result symlinks, or machine-local credentials. Keep sensitive settings manual unless already represented safely in the flake. Be careful with `hardware-configuration.nix`, network modules, boot settings, and service definitions because they affect bootability or connectivity.
