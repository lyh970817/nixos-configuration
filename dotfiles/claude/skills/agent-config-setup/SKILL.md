---
name: agent-config-setup
description: Use when configuring Claude Code, its config directories (CLAUDE_CONFIG_DIR), skills, commands, settings.json, profiles, or launchers on this machine. Not for other NixOS/Home Manager, host package, service, desktop, or launcher work.
---

# Agent Configuration (Claude)

## Model

The tracked source of truth is `/home/andongni/.nixos-config/dotfiles/claude/`. Home Manager module `home/programs/mutable-configs.nix` wires it into `$CLAUDE_CONFIG_DIR` mostly via `mkOutOfStoreSymlink` — an out-of-store symlink pointing at this repo checkout (`osConfig.portable.configDir`) instead of a store copy. **Edits to symlinked files are live immediately; no rebuild needed.**

- Symlinked (edit under `dotfiles/claude/`, changes are live at once): `CLAUDE.md`, `statusline.sh`, `skills/`, `commands/`, `output-styles/`.
- Materialized, not symlinked: `settings.json`. `dotfiles/claude/settings.json` is the tracked non-secret baseline. `home.activation.claudeSettings` (in `mutable-configs.nix`) jq-injects the current desktop theme (`dark-ansi` / `light-ansi`) into that baseline and installs the result as an ordinary mutable `0600` file at `$CLAUDE_CONFIG_DIR/settings.json` on every activation; `home/desktop/theming.nix` (`setClaudeTheme`) re-applies just the theme on every dark/light switch. Theme is the only intentional runtime variance — edit the tracked file, not the runtime copy, and rebuild to propagate non-theme changes.
- Machine-local mutable state, not sourced from the repo, not configuration to manage here: `.claude.json`, `.credentials.json`, `history.jsonl`, `projects/`, `sessions/`, `plugins/` (`installed_plugins.json`, `known_marketplaces.json` — managed via Claude's `/plugin` command), and caches. There is no `agents/` directory under `$CLAUDE_CONFIG_DIR`.

## Config directories

Claude has no Codex-style named profiles; each `CLAUDE_CONFIG_DIR` acts like a separate profile directory.

- Default: `/home/andongni/.config/claude` (default `CLAUDE_CONFIG_DIR`).
- `claude-mattpocock`: `/home/andongni/.config/claude-mattpocock`, selected by the `claude-matt` shell alias in `home/programs/shell.nix`, which sets `CLAUDE_CONFIG_DIR="$HOME/.config/claude-mattpocock"` before invoking `claude` (it's an alias, not a separate binary). `cly` / `clty` are `claude` / `claude-matt` with `--dangerously-skip-permissions`.
- `mutable-configs.nix` wires the same dotfiles sources into `claude-mattpocock` with `force = true`, but skills are wired per-skill, not as a whole `skills/` directory link: only `agent-config-setup` and `nix-environment-setup` (from `dotfiles/claude/skills/`) plus `visual-verification` (from the repo-root `skills/visual-verification`) are shared. Every other skill under `claude-mattpocock/skills` is independent and mutable, managed outside this repo.

## Launcher and package

- Launcher: `home/programs/claude.nix` (`writeShellApplication`) — sets proxy env (`HTTP_PROXY`/`HTTPS_PROXY`/`ALL_PROXY`/`NO_PROXY` and lowercase mirrors), locale (`LANG`/`LANGUAGE`/`LOCALE_ARCHIVE`), and `CLAUDE_CODE_*` env vars.
- Package derivation: `pkgs/claude-code.nix`.

## Workflow

1. Locate the tracked source under `dotfiles/claude/` first; edit there, never a runtime copy under `$CLAUDE_CONFIG_DIR`.
2. Keep edits scoped to the requested change.
3. Commit the change so the repo's pre-commit hooks are the verification gate (repo policy) — do this even for changes that are already live via symlink.
4. Rebuild with `sudo nixos-rebuild switch --flake .#system --impure` (or the `rebuild` alias, which targets `/etc/nixos#system` and works from any directory) only when the change touches the materialized `settings.json` or Nix wiring itself (`mutable-configs.nix`, `theming.nix`, `claude.nix`, `pkgs/claude-code.nix`). Pure content edits to symlinked files (`CLAUDE.md`, `skills/`, `commands/`, `output-styles/`, `statusline.sh`) are already live — commit only, no rebuild required.
