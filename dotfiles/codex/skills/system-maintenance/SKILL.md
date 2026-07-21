---
name: system-maintenance
description: System-wide and user-environment maintenance and configuration workflow for this machine. Use for tasks outside an individual project's source or project-local configuration, including NixOS or Home Manager changes, host packages, services, desktop and launcher configuration, rebuilds, declarative machine or user state, mutable per-user runtime or configuration state, and configuring Codex, Claude, Claude Code, AI agents, skills, skills.sh, profiles, plugins, launchers, or agent config directories.
---

# System Maintenance

Use `/home/andongni/.nixos-config` as the source of truth for this machine's NixOS and Home Manager configuration.

## Workflow

1. Establish the ownership boundary: determine whether the task belongs to an individual project's source or project-local configuration, declarative NixOS/Home Manager state, or mutable per-user runtime or configuration state. Use this skill for the latter two, and inspect the effective configuration and runtime paths before changing state. Completion criterion: the owning layer and a non-destructive maintenance path are identified.
2. For machine-level maintenance, start in `/home/andongni/.nixos-config` and read the local guidance such as `AGENTS.md` before editing. Completion criterion: the relevant repo rules and current file layout are known.
3. For Codex, Claude, or other AI-agent configuration, use the configuration map below before choosing whether the change belongs in mutable agent state or the NixOS/Home Manager repo. Completion criterion: the active profile, config directory, and launcher path are identified.
4. Make scoped configuration changes in the existing NixOS/Home Manager structure or mutable agent config structure. Completion criterion: only files needed for the requested maintenance task are changed.
5. If applying the NixOS/Home Manager configuration is needed, rebuild from that repo with `sudo nixos-rebuild switch --flake .#andongni --impure`. Completion criterion: the rebuild command is run from `/home/andongni/.nixos-config`, or the user is told why it was not run.

## AI Agent Configuration Map

Codex mutable state lives under `/home/andongni/.codex`.

- Base Codex config: `/home/andongni/.codex/config.toml`.
- Separate Codex profiles: `/home/andongni/.codex/*.config.toml`, selected with `codex --profile <name>`.
- Codex skill entries: `[[skills.config]]` stanzas target skill directories containing `SKILL.md`, with `enabled = true` or `false`.
- Portable relative profile paths are resolved from the profile's runtime location under `/home/andongni/.codex`: `skills/<skill>` targets `/home/andongni/.codex/skills/<skill>`, while `../.agents/skills/<skill>` targets `/home/andongni/.agents/skills/<skill>`.
- Global Codex skills: `/home/andongni/.codex/skills/<skill>/SKILL.md`.
- System Codex skills: `/home/andongni/.codex/skills/.system/<skill>/SKILL.md`.
- Shared/user workflow skills used by profiles: `/home/andongni/.agents/skills/<skill>/SKILL.md`.
- Codex automatically scans both `/home/andongni/.codex/skills` and `/home/andongni/.agents/skills` for every user config layer. If a managed skill set lives under `/home/andongni/.agents/skills` but should not appear in the base profile, add explicit base-profile `[[skills.config]]` name disables for the unwanted skills; profile-specific path enables can re-enable them when launched with `codex --profile <name>`.
- A global Codex skill should live once in the global Codex skills folder, for example `/home/andongni/.codex/skills/system-maintenance/SKILL.md`; do not duplicate it into each Codex profile. Enable or reference it through Codex's global/profile configuration so it is available to all profiles.
- Codex skills may be installed or updated with the `npx skills@latest` CLI linked by the skills.sh ecosystem. Follow upstream installation instructions and check `/home/andongni/.local/state/skills/.skill-lock.json` for managed sources and update metadata. Matt Pocock publishes one portable source rather than separate Codex and Claude editions: the selected agent controls registration and installation location.
- Codex curated skills may also be installed with `$skill-installer`; distinguish those from `npx skills@latest` managed skills before changing or updating them.
- When updating a whole managed skill set, delete skills that the upstream source has removed; do not leave stale copied folders, lock entries, or Codex profile entries pointing at removed upstream skills.
- For synchronizing the complete `mattpocock/skills` installation, removing deprecated upstream skills, and maintaining Codex profile boundaries, invoke `$sync-mattpocock-skills`.
- Keep whole skill sets in their own Codex profile, for example `/home/andongni/.codex/mattpocock.config.toml` for Matt Pocock skills. Only include individual skills from that set in other profiles when they are explicitly needed there.
- Codex Desktop installation and CLI wrapper: `/home/andongni/.nixos-config/home/programs/codex-desktop.nix`.

Claude mutable state lives under `CLAUDE_CONFIG_DIR`.

- Default Claude config dir: `/home/andongni/.config/claude`.
- Claude launcher and default environment: `/home/andongni/.nixos-config/home/programs/claude.nix`.
- Claude Code package derivation: `/home/andongni/.nixos-config/pkgs/claude-code.nix`.
- Claude settings: `$CLAUDE_CONFIG_DIR/settings.json`.
- Claude guidance: `$CLAUDE_CONFIG_DIR/CLAUDE.md`.
- Claude commands, agents, plugins, and skills: `$CLAUDE_CONFIG_DIR/commands`, `$CLAUDE_CONFIG_DIR/agents`, `$CLAUDE_CONFIG_DIR/plugins`, and `$CLAUDE_CONFIG_DIR/skills`.
- Separate Claude profile example: `claude-matt` sets `CLAUDE_CONFIG_DIR="$HOME/.config/claude-mattpocock"` in `/home/andongni/.nixos-config/home/programs/shell.nix`.
- `dotfiles/claude/settings.json` is the tracked non-secret baseline. Home Manager materializes independent mutable settings files for the default and Matt profiles, and theme automation updates both from `/home/andongni/.nixos-config/home/desktop/theming.nix`.
- Claude plugins are managed through Claude's `/plugin` commands; installed plugin state is in `$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json` and known marketplaces are in `$CLAUDE_CONFIG_DIR/plugins/known_marketplaces.json`.
- Claude does not have Codex-style profiles, but each `CLAUDE_CONFIG_DIR` acts like a separate profile folder. Keep the Claude-format `system-maintenance` skill present in every Claude config dir's `skills` folder, using symlinks where appropriate, for example `/home/andongni/.config/claude/skills/system-maintenance` and `/home/andongni/.config/claude-mattpocock/skills/system-maintenance`.

Portable upstream Agent Skills may use identical `SKILL.md` content for Codex and Claude, but keep their installation trees, selected agent targets, profiles, and update lifecycles explicit. Locally authored agent-specific workflows such as `system-maintenance` and `sync-mattpocock-skills` use separate Codex and Claude implementations when their paths or behavior differ; do not symlink Claude to Codex's local workflow files. Use `npx skills@latest` to list, add, remove, check, or update a source when `/home/andongni/.local/state/skills/.skill-lock.json` shows that it is managed by that CLI.

## Rebuild Discipline

For configuration changes in this repo, follow the repository rebuild policy: commit the scoped change first so the configured pre-commit hooks run verification, then apply the committed configuration with `sudo nixos-rebuild switch --flake .#andongni --impure`. If the rebuild fails, make a follow-up fix commit and rebuild again.
