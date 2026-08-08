# Repository Guidelines

## Project Structure & Module Organization

This repository is one generic NixOS flake configuration serving two machines: the `linglong` home desktop and a remote portable laptop, selected via a `portable.role` split (`"home"` / `"remote"`). Entry points are `flake.nix`, `configuration.nix`, and `hardware-configuration.nix`. System modules live under `modules/`: `system/`, `desktop/`, `hardware/`, `services/`, and `programs/`. Home Manager starts at `home/andongni.nix`; user modules are in `home/programs/`, packages in `home/packages/`, and desktop settings in `home/desktop/`. Custom derivations are in `pkgs/`; user accounts are under `users/`. Managed dotfiles and assets are in `dotfiles/` and `assets/`. Notes belong in `docs/`.

The flake exposes a single `.#system` output for both machines; per-machine facts (hardware, hostname, and `portable.role`/`peerHost`/`configDir`) come from gitignored `/etc/nixos/hardware-configuration.nix` and `/etc/nixos/local.nix`, imported by absolute path (hence `--impure`). Modules gated on `osConfig.portable.role == "home"` give the remote laptop a lighter package/feature set.

## Build, Test, and Development Commands

- `rebuild`: apply the configuration to the local host. The alias invokes `sudo nixos-rebuild switch --flake /etc/nixos#system --impure`, so it works from any directory through the stable `/etc/nixos` checkout symlink.
- `sudo nixos-rebuild switch --flake .#system --impure`: apply the configuration directly when already in this checkout.
- `find . -name '*.nix' -print0 | xargs -0 nixfmt`: format Nix files.

## Rebuild Policy

For configuration changes, do not run standalone verification commands before rebuilding. Stage and commit the scoped change first, then apply the committed configuration with `rebuild`.

`rebuild` is the verification gate: a full evaluation and build catches every syntax, type, missing-attr, and build error, so running separate checks beforehand only duplicates it. The pre-commit hooks are deliberately *not* that gate — they cover only what a rebuild structurally cannot see (nixfmt drift, TOML/JSON parse errors in files Home Manager installs as opaque bytes, merge-conflict markers, private keys). A clean commit therefore does not mean the configuration evaluates; only a successful `rebuild` means that. The hooks install themselves at Home Manager activation (`home/programs/pre-commit.nix`), so a fresh clone picks them up on its first rebuild.

For visual changes, perform visual verification automatically. Treat
the mode active at task start as the entire change scope; change or inspect the
other mode only when the user explicitly requests it. Before committing, a
visual preview may use reliably reversible runtime overrides or isolated
temporary configs. It must not run an uncommitted Home Manager activation or
NixOS rebuild. Commit and rebuild the selected result, then visually inspect the
installed result through `screen-verify`.

## Mihomo Configuration: Safe Apply / Auto-Revert

The mihomo config lives at `secrets/mihomo-config.yaml`. It is out-of-store and
git-ignored (it may hold sensitive local data), wired to the service by absolute
path via `LoadCredential`. Because the unit text is content-independent, editing
the file does **nothing** until the service restarts: `rebuild` does not restart
mihomo — the config only goes live on a mihomo restart.

Your own model connection is reached **through mihomo**. If an edit breaks
connectivity you go silent and cannot act. So applying a config change is guarded
by a dead-man's switch, keyed on your confirmation, not on any connectivity probe.

When you (or the user) edit `secrets/mihomo-config.yaml`, apply it with:

```sh
sudo mihomo-guard try        # optional: sudo mihomo-guard try 120  (custom timeout)
```

This records nothing new yet: it arms a detached 90-second auto-revert timer,
then restarts mihomo so the edit goes live. Note this briefly interrupts **all**
traffic (TUN restart).

- If the edit is good and you can still reach your model, confirm it:

  ```sh
  sudo mihomo-guard keep
  ```

  This disarms the timer and records the current live config as the new baseline
  (`/var/lib/mihomo-config/last-good.yaml`).

- If the edit is bad but you are **still connected**, undo it now:

  ```sh
  sudo mihomo-guard revert
  ```

- If the edit **breaks your connection**, do nothing (you cannot). After 90
  seconds the timer fires autonomously, restores the last-good config, restarts
  mihomo, and your connection comes back. Do not attempt a manual revert while
  disconnected — the system handles it.

Whenever a change is reverted or auto-reverted, the rejected config is preserved
at `/var/lib/mihomo-config/rejected.yaml` (overwriting any previous one). After
your connection returns you can inspect that file to see what you tried and retry
from there.

A reboot during the pending window is treated as a failed change: a boot-time
oneshot restores last-good before mihomo starts (also preserving the rejected
edit to `rejected.yaml`).

**Bootstrap (do this once now):** with your connection working, run

```sh
sudo mihomo-guard keep
```

to record the current working config as the baseline. `mihomo-guard try` refuses
to run until a baseline exists. Inspect state any time with:

```sh
mihomo-guard status
```

## Coding Style & Naming Conventions

Use two-space indentation in Nix files. Keep modules focused on one concern and name files by feature, for example `modules/services/keyd.nix` or `home/programs/tmux.nix`. Prefer explicit imports in aggregator files over hidden dynamic loading. Keep comments brief around hardware, network, or host-specific behavior.

## hyprwhspr Packaging

`pkgs/hyprwhspr.nix` should package upstream runtime files that shipped commands depend on, including `bin`, `config`, `lib`, `share`, `scripts`, and `utils`. Expose user-facing upstream launchers with wrappers in `$out/bin`; auxiliary tools such as `meeting-recorder` must not live only under `$out/lib/hyprwhspr/bin`. Copy upstream docs, contrib files, and license material to `$out/share/doc/hyprwhspr`. The local host uses hyprwhspr with the REST backend; do not assume local backends such as `pywhispercpp` work unless their Python dependencies are explicitly added to the Nix environment.

## Commit & Pull Request Guidelines

Recent history uses short imperative subjects such as `Add 115 Browser launcher` and `Fix tmux copy-mode paging keys`. Follow that style: start with a verb, keep the subject specific, and avoid unrelated changes in one commit. Never push branches and never open pull requests, even from an isolated worktree — leave completed work committed on its local branch and let the user push and merge it themselves.

Commit configuration changes before rebuilding, then treat `rebuild` as the verification gate (see Rebuild Policy — the pre-commit hooks are only a formatting and hygiene screen, not a correctness check). If the rebuild fails, make a follow-up fix commit and rebuild again.

## Security & Configuration Tips

Do not commit secrets, private SSH material, generated result symlinks, or machine-local credentials. Keep sensitive settings manual unless already represented safely in the flake. Be careful with `hardware-configuration.nix`, network modules, boot settings, and service definitions because they affect bootability or connectivity.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
