---
name: agent-config-setup
description: Use when configuring Claude Code, Codex, AI agents, skills, profiles, plugins, launchers, or agent config directories on this machine. Not for other NixOS/Home Manager, host package, service, desktop, or launcher work.
---

# Agent Configuration

## Claude

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

## Codex

Tracked source of truth: `/home/andongni/.nixos-config/dotfiles/codex/` (plus `dotfiles/agents/skills` for the shared skill pool). `mutable-configs.nix` wires it into `~/.codex` the same way: symlinked content is live immediately, no rebuild needed.

- Symlinked: `AGENTS.md`, `rules/`, `skills/` — 13 tracked Codex-specific skills (includes this skill and `sync-mattpocock-skills`).
- Copied, not linked: profiles. `home.activation.codexProfiles` copies `dotfiles/codex/profiles/*.config.toml` to `~/.codex/<name>.config.toml` on every activation (6 tracked profiles: `last30days`, `lavish-axi`, `mattpocock`, `openai`, `superpowers`, `understand-anything-codegraph`), so their relative skill paths resolve from `~/.codex`. Editing a runtime `~/.codex/*.config.toml` is futile — it's overwritten on the next rebuild; edit `dotfiles/codex/profiles/<name>.config.toml` and rebuild to propagate.
- `~/.codex/shared-skills` is a separate out-of-store symlink to `dotfiles/agents/skills` — a curated, shared 36-skill pool used across profiles, not Codex-specific. It's CLI-only: Codex Desktop's `CODEX_HOME` is `~/.codex-desktop`, which never reads `~/.codex`, so Desktop never sees this symlink.
- The engine auto-scans two sources regardless of profile: `$HOME/.agents/skills` as a USER-scope source (independent of `CODEX_HOME`) and bundled `.system` skills under `$CODEX_HOME/skills/.system` (verified in v0.144.5 source, `core-skills/src/loader.rs`) — anything placed at `$HOME/.agents/skills` would auto-load into every Codex surface, including Desktop, with no per-skill opt-out, which is why that path must never exist on this machine. The shared pool instead lives at `dotfiles/agents/skills`, reached only via `~/.codex/shared-skills`. Beyond that `.system` auto-scan, a profile enables a skill only via an explicit `[[skills.config]]` stanza with a path resolved relative to the profile's runtime location under `~/.codex`: `skills/<name>` targets `~/.codex/skills/<name>`, `shared-skills/<name>` targets `~/.codex/shared-skills/<name>` (the pool). Select a profile with `codex --profile <name>`.
- Mutable, not sourced from the repo: `config.toml`, `auth.json`, sqlite state, `history.jsonl`, `sessions/`, caches.
- CLI package derivation: `pkgs/codex.nix`, wired via `home/programs/codex-desktop.nix` (`home.packages`); Codex Desktop (GUI) uses `pkgs/codex-desktop-isolated.nix` through the same module and keeps its state under `~/.codex-desktop`, isolated from the CLI. Shell alias `cdy` runs `codex --yolo` (bypasses approval prompts, unrelated to profile selection).
- Codex Desktop's `~/.codex-desktop/config.toml` is fresh app-owned mutable state, not repo-managed: nothing in this repo writes to it.
- Claude does not consume the pool: it's not shared with Codex's whole-directory `~/.codex/shared-skills` symlink. If a pool skill is ever needed there, share it the way `claude-mattpocock` shares `visual-verification` today — a per-skill relative symlink inside `dotfiles/claude/skills/`, not a directory-wide link.

## Workflow

1. Locate the tracked source under `dotfiles/claude/` (Claude) or `dotfiles/codex/` / `dotfiles/agents/` (Codex) first; edit there, never a runtime copy under `$CLAUDE_CONFIG_DIR` or `~/.codex`.
2. Keep edits scoped to the requested change.
3. Commit the change so the repo's pre-commit hooks are the verification gate (repo policy) — do this even for changes that are already live via symlink.
4. Rebuild with `sudo nixos-rebuild switch --flake .#system --impure` (or the `rebuild` alias, which targets `/etc/nixos#system` and works from any directory) only when the change touches a materialized/copied file (`settings.json`, a Codex profile under `dotfiles/codex/profiles/`) or Nix wiring itself (`mutable-configs.nix`, `theming.nix`, `claude.nix`, `codex-desktop.nix`, `pkgs/claude-code.nix`, `pkgs/codex.nix`, `pkgs/codex-desktop-isolated.nix`). Pure content edits to symlinked files (`CLAUDE.md`, `skills/`, `commands/`, `output-styles/`, `statusline.sh`, `AGENTS.md`, `rules/`, `dotfiles/agents/skills/`) are already live — commit only, no rebuild required.
