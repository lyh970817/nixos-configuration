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

## Guarded Mihomo Deployments

`mihomo-config.yaml` is intentionally ignored because it may contain sensitive
local configuration. Its tracked, non-secret identity is
`mihomo-config.sha256`. After changing the YAML, update that file with the
YAML's SHA-256 hash without committing or printing the YAML itself. Changes to
the identity file and/or `modules/services/mihomo.nix` must be made in a
dedicated commit containing no other paths, then deployed only with the guarded
workflow:

```sh
sudo scripts/mihomo-safe-rebuild.sh switch
sudo scripts/mihomo-safe-rebuild.sh status
sudo scripts/mihomo-safe-rebuild.sh confirm TRANSACTION_ID
sudo scripts/mihomo-safe-rebuild.sh rollback TRANSACTION_ID
```

`switch` completely builds the candidate before it records the current
`/run/current-system` closure. It refuses to begin unless that closure is also
the persistent system profile and then arms a fixed 60-second root-owned
transient systemd timer. The timer runs a root-owned helper in `/run` which
takes the transaction lock and restores the recorded profile, boot target, and
live closure directly. It never evaluates the flake, rebuilds, uses the
network, or reads repository state. The candidate is activated with `test`, so
the known-good profile and boot target remain in place until confirmation. The
candidate activation command waits at most 10 seconds; systemd work it already
submitted may continue, so readiness is determined by the active closure,
`mihomo.service`, and its localhost REST API before the fixed deadline. The
independent rollback helper remains responsible for recovery. It verifies the
ignored YAML against its committed identity before and after the
build/activation; dirty files outside the identity and Mihomo service module do
not block deployment. Do not use a plain `nixos-rebuild switch` for these
changes.

Confirm only after at least 20 seconds and a fresh round trip through the
agent. It requires the transaction ID from `status`, an armed timer, the active
candidate, active `mihomo.service`, a responsive localhost REST API, and an
unexpired stored deadline. It promotes the exact tested closure
without rebuilding while the timer remains armed, marks the transaction
confirmed, then stops the timer and helper before it releases the transaction
lock. A lost connection, activation error, or promotion error leaves the timer
armed to restore the known-good closure. Recovery bounds any required profile,
boot-target, and live-activation commands separately, then polls the active
closure, persistent profile, service, and REST API; it removes volatile state
only after all are healthy. A reboot before confirmation naturally boots the
still-default known-good closure. The root-only state record and helper live
only in `/run`. Neither recovery path reverts Git.

## Coding Style & Naming Conventions

Use two-space indentation in Nix files. Keep modules focused on one concern and name files by feature, for example `modules/services/keyd.nix` or `home/programs/tmux.nix`. Prefer explicit imports in aggregator files over hidden dynamic loading. Keep comments brief around hardware, network, or host-specific behavior.

## hyprwhspr Packaging

`pkgs/hyprwhspr.nix` should package upstream runtime files that shipped commands depend on, including `bin`, `config`, `lib`, `share`, `scripts`, and `utils`. Expose user-facing upstream launchers with wrappers in `$out/bin`; auxiliary tools such as `meeting-recorder` must not live only under `$out/lib/hyprwhspr/bin`. Copy upstream docs, contrib files, and license material to `$out/share/doc/hyprwhspr`. The local host uses hyprwhspr with the REST backend; do not assume local backends such as `pywhispercpp` work unless their Python dependencies are explicitly added to the Nix environment.

## Commit & Pull Request Guidelines

Recent history uses short imperative subjects such as `Add 115 Browser launcher` and `Fix tmux copy-mode paging keys`. Follow that style: start with a verb, keep the subject specific, and avoid unrelated changes in one commit. Pull requests should summarize changes, list validation commands, call out host-specific effects, and include screenshots only for UI changes.

Commit configuration changes before rebuilding. Treat the pre-commit hooks as the verification gate before `sudo nixos-rebuild switch --flake .#andongni --impure`; if the rebuild fails, make a follow-up fix commit and rebuild again.

## Security & Configuration Tips

Do not commit secrets, private SSH material, generated result symlinks, or machine-local credentials. Keep sensitive settings manual unless already represented safely in the flake. Be careful with `hardware-configuration.nix`, network modules, boot settings, and service definitions because they affect bootability or connectivity.
