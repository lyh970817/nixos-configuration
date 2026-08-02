---
name: agent-config-setup
description: Configuration workflow for Codex, its config directory (~/.codex), skills, profiles, or launchers on this machine. Not for other NixOS/Home Manager, host package, service, desktop, or launcher work.
---

# Agent Configuration (Codex)

## Model

The tracked sources of truth are `/home/andongni/.nixos-config/dotfiles/codex/` for seven Codex-authored skills including `lavish` and `/home/andongni/.nixos-config/dotfiles/universal-skills/` for the five universal skills (`bro`, `domain-context`, `nix-environment-setup`, `r-dev-shell`, and `visual-verification`), plus `dotfiles/agents/skills` for the separate Matt Pocock-managed shared pool. Home Manager module `home/programs/mutable-configs.nix` wires it into `~/.codex` mostly via `mkOutOfStoreSymlink` — an out-of-store symlink pointing at this repo checkout (`osConfig.portable.configDir`) instead of a store copy. **Edits to symlinked files are live immediately; no rebuild needed.**

- Symlinked: `AGENTS.md`, `rules/`, seven Codex-authored skill entries (`agent-config-setup`, `sync-mattpocock-skills`, `codex-dynamic-workflows`, `commit-guidelines`, `lavish`, `root-browser-control`, `superpowers-domain-context`), and five universal bridge entries (`bro`, `domain-context`, `nix-environment-setup`, `r-dev-shell`, `visual-verification`). The Codex-authored skills, including `lavish`, are sourced from `dotfiles/codex/skills/`; the five universal bridges are sourced from `dotfiles/universal-skills/`. `lavish` is not a universal bridge and is not exposed to Claude or OMP.
- Copied, not linked: profiles. `home.activation.codexProfiles` copies `dotfiles/codex/profiles/*.config.toml` to `~/.codex/<name>.config.toml` on every activation (six tracked profiles: `last30days`, `lavish-axi`, `mattpocock`, `openai`, `superpowers`, `understand-anything-codegraph`). They are copied rather than symlinked so each profile's relative skill paths resolve correctly from `~/.codex`. Editing a runtime `~/.codex/*.config.toml` directly is futile — it is overwritten on the next `nixos-rebuild switch`; edit `dotfiles/codex/profiles/<name>.config.toml` instead and rebuild to propagate.
- `~/.codex/shared-skills` is a separate out-of-store symlink to `dotfiles/agents/skills` — a Matt Pocock-managed, curated, shared 36-skill pool used across profiles, not Codex-specific or universal. It must not be linked into Claude. It's CLI-only: Codex Desktop's `CODEX_HOME` is `~/.codex-desktop`, which never reads `~/.codex`, so Desktop never sees this symlink.
- Mutable, not sourced from the repo, not configuration to manage here: `config.toml` (base config), `auth.json`, sqlite state, `history.jsonl`, `sessions/`, shell snapshots, caches.

## How profiles select skills

The engine auto-scans two sources regardless of profile: `$HOME/.agents/skills` as a USER-scope source (independent of `CODEX_HOME`) and bundled `.system` skills under `$CODEX_HOME/skills/.system`. `$HOME/.agents/skills` must never exist on this machine — anything placed there auto-loads into every Codex surface, including Desktop, with no per-skill opt-out. The shared pool instead lives at `dotfiles/agents/skills`, reached only via `~/.codex/shared-skills`.

Beyond that `.system` auto-scan, a profile enables a skill only by explicitly listing a `[[skills.config]]` stanza whose path is resolved relative to the profile file's own runtime location under `~/.codex`:

- `skills/<name>` resolves to `~/.codex/skills/<name>` (from `dotfiles/codex/skills/`; only the five universal bridge names resolve to canonical sources in `dotfiles/universal-skills/`, while `lavish` resolves to the Codex-authored source).
- `shared-skills/<name>` resolves to `~/.codex/shared-skills/<name>` (from `dotfiles/agents/skills/`, the shared pool).

Select a profile with `codex --profile <name>`. To add or drop a skill from a profile, edit the profile's `[[skills.config]]` stanzas in `dotfiles/codex/profiles/<name>.config.toml`.

For synchronizing the whole Matt Pocock skill set, see the `sync-mattpocock-skills` skill (`dotfiles/codex/skills/sync-mattpocock-skills`) — it is a plain git-tracked Codex skill, not an externally managed install flow.

## Launcher and package

- CLI package derivation: `pkgs/codex.nix`; the CLI runs directly against `~/.codex` (`home/programs/codex-desktop.nix` adds `pkgs.codex` to `home.packages`). Shell alias `cdy` runs `codex --yolo` (bypasses approval prompts).
- Codex Desktop (GUI) is wired through the same `home/programs/codex-desktop.nix` via `programs.codexDesktopLinux`, using `pkgs.codex-desktop-isolated` (`pkgs/codex-desktop-isolated.nix`), which wraps the desktop app to keep its state under `~/.codex-desktop`/isolated XDG dirs instead of `~/.codex`, so it does not share state with the CLI.

## Workflow

1. Locate the tracked source under `dotfiles/codex/` for the seven Codex-authored skills (including `lavish`), `dotfiles/universal-skills/` for the five universal skills, or `dotfiles/agents/skills` for the separate Matt Pocock-managed shared pool first; edit there, never a runtime copy under `~/.codex`.
2. Keep edits scoped to the requested change.
3. Commit the change so the repo's pre-commit hooks are the verification gate (repo policy) — do this even for changes that are already live via symlink.
4. Rebuild with `sudo nixos-rebuild switch --flake .#system --impure` (or the `rebuild` alias, which targets `/etc/nixos#system` and works from any directory) only when the change touches a copied profile (`dotfiles/codex/profiles/*.config.toml`) or Nix wiring itself (`mutable-configs.nix`, `codex-desktop.nix`, `pkgs/codex.nix`, `pkgs/codex-desktop-isolated.nix`). Pure content edits to runtime-linked files (`AGENTS.md`, `rules/`, the five universal bridges, `dotfiles/agents/skills/`, and the Codex-authored `dotfiles/codex/skills/`) are already live — commit only, no rebuild required.
