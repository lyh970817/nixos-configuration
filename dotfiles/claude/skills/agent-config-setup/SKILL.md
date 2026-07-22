---
name: agent-config-setup
description: Use when configuring Codex, Claude, Claude Code, AI agents, skills, skills.sh, npx skills, profiles, plugins, launchers, or agent config directories on this machine. Use system-maintenance instead for NixOS/Home Manager, host packages, services, desktop, launcher, or rebuild work unrelated to agent configuration.
---

# Agent Configuration

## Workflow

1. Identify the active profile, config directory, and launcher path before editing mutable agent state or NixOS/Home Manager files.
2. Keep edits scoped to the requested agent-configuration task and to the existing configuration structure.
3. If the change lives in `/home/andongni/.nixos-config` (this skill's own files, other tracked dotfiles, or launcher derivations), commit the scoped change first so the configured pre-commit hooks are the verification gate, then apply with `sudo nixos-rebuild switch --flake .#andongni --impure` from that repo.

## Codex

Codex mutable state lives under `/home/andongni/.codex`.

- Base Codex config: `/home/andongni/.codex/config.toml`.
- Separate Codex profiles: `/home/andongni/.codex/*.config.toml`, selected with `codex --profile <name>`.
- Codex skill entries: `[[skills.config]]` stanzas target skill directories containing `SKILL.md`, with `enabled = true` or `false`.
- Portable relative profile paths are resolved from the profile's runtime location under `/home/andongni/.codex`: `skills/<skill>` targets `/home/andongni/.codex/skills/<skill>`, while `../.agents/skills/<skill>` targets `/home/andongni/.agents/skills/<skill>`.
- Global Codex skills live once under `/home/andongni/.codex/skills/<skill>/SKILL.md`; a global Codex skill is enabled or referenced through Codex configuration for all profiles, not copied into each profile.
- System Codex skills: `/home/andongni/.codex/skills/.system/<skill>/SKILL.md`.
- Shared/user workflow skills used by profiles: `/home/andongni/.agents/skills/<skill>/SKILL.md`.
- Codex skills may be installed or updated with the `npx skills@latest` CLI linked by the skills.sh ecosystem, and managed sources are tracked in `/home/andongni/.local/state/skills/.skill-lock.json`.
- When updating a whole managed skill set, delete skills that the upstream source removed; also remove stale lock entries and Codex profile entries.
- Keep whole skill sets in their own Codex profile, for example `/home/andongni/.codex/mattpocock.config.toml`, except for individual skills explicitly included in other profiles.

## Claude

Claude mutable state lives under `CLAUDE_CONFIG_DIR`.

- Default Claude config dir: `/home/andongni/.config/claude`.
- Claude mattpocock config dir: `/home/andongni/.config/claude-mattpocock`, selected by the `claude-matt` launcher.
- Claude launcher and default environment: `/home/andongni/.nixos-config/home/programs/claude.nix`.
- Claude Code package derivation: `/home/andongni/.nixos-config/pkgs/claude-code.nix`.
- Claude settings: `$CLAUDE_CONFIG_DIR/settings.json`.
- Claude guidance: `$CLAUDE_CONFIG_DIR/CLAUDE.md`.
- Claude commands, agents, plugins, and skills: `$CLAUDE_CONFIG_DIR/commands`, `$CLAUDE_CONFIG_DIR/agents`, `$CLAUDE_CONFIG_DIR/plugins`, and `$CLAUDE_CONFIG_DIR/skills`.
- Matt Pocock skills in the `claude-mattpocock` profile are independent copies managed with the upstream-recommended `npx skills@latest add mattpocock/skills` flow. For exact synchronization and removal of deprecated skills, invoke `$sync-mattpocock-skills` from that profile; never link those skills to `/home/andongni/.agents/skills` or `/home/andongni/.codex/skills`.
- `claude-matt` sets `CLAUDE_CONFIG_DIR="$HOME/.config/claude-mattpocock"` in `/home/andongni/.nixos-config/home/programs/shell.nix`.
- `dotfiles/claude/settings.json` is the tracked non-secret baseline for every shared Claude setting. Home Manager replaces both independent, ordinary runtime files with that baseline on activation, deriving only their theme from the active desktop mode; theme automation in `/home/andongni/.nixos-config/home/desktop/theming.nix` is the only intentional runtime settings variance.
- Claude plugins are managed through Claude's `/plugin` commands; installed plugin state is in `$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json` and known marketplaces are in `$CLAUDE_CONFIG_DIR/plugins/known_marketplaces.json`.

Claude does not have Codex-style profiles, but each `CLAUDE_CONFIG_DIR` acts like a separate profile folder. Keep this Claude-format `agent-config-setup` skill present in every Claude config dir's `skills` folder, using symlinks where appropriate:

- `/home/andongni/.config/claude/skills/agent-config-setup`
- `/home/andongni/.config/claude-mattpocock/skills/agent-config-setup`

Portable upstream Agent Skills may use identical `SKILL.md` content for Codex and Claude, but keep their installation trees, selected agent targets, config directories, and update lifecycles explicit. Locally authored agent-specific workflows such as `agent-config-setup`, `system-maintenance`, and `sync-mattpocock-skills` use separate Codex and Claude implementations when their paths or behavior differ. Do not symlink this Claude workflow to `/home/andongni/.codex/skills/agent-config-setup/SKILL.md`.
