---
name: system-maintenance
description: Use when the user asks for system maintenance, NixOS or Home Manager changes, host package, service, desktop, launcher, or rebuild work, machine-level troubleshooting, or configuring Codex, Claude, Claude Code, AI agents, skills, skills.sh, npx skills, profiles, plugins, launchers, or agent config directories on this machine.
---

# System Maintenance

Use `/home/andongni/.nixos-config` as the source of truth for this machine's NixOS and Home Manager configuration. If the configuration must be rebuilt, rebuild from that repo with `sudo nixos-rebuild switch --flake .#andongni --impure`.

## Workflow

1. For machine-level maintenance, start in `/home/andongni/.nixos-config` and read local guidance such as `AGENTS.md` before editing.
2. For Codex, Claude, or other AI-agent configuration, identify the active profile, config directory, and launcher path before editing mutable state or NixOS/Home Manager files.
3. Keep edits scoped to the requested maintenance task and to the existing configuration structure.
4. For NixOS/Home Manager changes, commit the scoped change before rebuilding so the configured pre-commit hooks are the verification gate.

## Agent Configuration Map

Codex mutable state lives under `/home/andongni/.codex`.

- Base Codex config: `/home/andongni/.codex/config.toml`.
- Separate Codex profiles: `/home/andongni/.codex/*.config.toml`, selected with `codex --profile <name>`.
- Codex skill entries: `[[skills.config]]` stanzas pointing at `SKILL.md` files with `enabled = true` or `false`.
- Global Codex skills live once under `/home/andongni/.codex/skills/<skill>/SKILL.md`; a global Codex skill is enabled or referenced through Codex configuration for all profiles, not copied into each profile.
- System Codex skills: `/home/andongni/.codex/skills/.system/<skill>/SKILL.md`.
- Shared/user workflow skills used by profiles: `/home/andongni/.agents/skills/<skill>/SKILL.md`.
- Codex skills may be installed or updated with the `npx skills@latest` CLI linked by the skills.sh ecosystem, and managed sources are tracked in `/home/andongni/.local/state/skills/.skill-lock.json`.
- When updating a whole managed skill set, delete skills that the upstream source removed; also remove stale lock entries and Codex profile entries.
- Keep whole skill sets in their own Codex profile, for example `/home/andongni/.codex/mattpocock.config.toml`, except for individual skills explicitly included in other profiles.

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
- Theme automation mutates `/home/andongni/.config/claude/settings.json` from `/home/andongni/.nixos-config/home/desktop/theming.nix`.
- Claude plugins are managed through Claude's `/plugin` commands; installed plugin state is in `$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json` and known marketplaces are in `$CLAUDE_CONFIG_DIR/plugins/known_marketplaces.json`.

Claude does not have Codex-style profiles, but each `CLAUDE_CONFIG_DIR` acts like a separate profile folder. Keep this Claude-format `system-maintenance` skill present in every Claude config dir's `skills` folder, using symlinks where appropriate:

- `/home/andongni/.config/claude/skills/system-maintenance`
- `/home/andongni/.config/claude-mattpocock/skills/system-maintenance`

Portable upstream Agent Skills may use identical `SKILL.md` content for Codex and Claude, but keep their installation trees, selected agent targets, config directories, and update lifecycles explicit. Locally authored agent-specific workflows such as `system-maintenance` and `sync-mattpocock-skills` use separate Codex and Claude implementations when their paths or behavior differ. Do not symlink this Claude workflow to `/home/andongni/.codex/skills/system-maintenance/SKILL.md`.

## Rebuild Discipline

For configuration changes in `/home/andongni/.nixos-config`, follow the repo policy: commit the scoped change first, then apply the committed configuration with `sudo nixos-rebuild switch --flake .#andongni --impure`. If the rebuild fails, make a follow-up fix commit and rebuild again.
