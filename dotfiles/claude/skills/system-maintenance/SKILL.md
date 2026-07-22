---
name: system-maintenance
description: Use when the user asks for system maintenance, NixOS or Home Manager changes, host package, service, desktop, launcher, or rebuild work, or machine-level troubleshooting. Use agent-config-setup instead for configuring Codex, Claude, Claude Code, AI agents, skills, skills.sh, npx skills, profiles, plugins, launchers, or agent config directories.
---

# System Maintenance

Use `/home/andongni/.nixos-config` as the source of truth for this machine's NixOS and Home Manager configuration. If the configuration must be rebuilt, rebuild from that repo with `sudo nixos-rebuild switch --flake .#andongni --impure`.

## Workflow

1. Start in `/home/andongni/.nixos-config` and read local guidance such as `AGENTS.md` before editing.
2. Keep edits scoped to the requested maintenance task and to the existing configuration structure.
3. Commit the scoped change before rebuilding so the configured pre-commit hooks are the verification gate.

## Rebuild Discipline

For configuration changes in `/home/andongni/.nixos-config`, follow the repo policy: commit the scoped change first, then apply the committed configuration with `sudo nixos-rebuild switch --flake .#andongni --impure`. If the rebuild fails, make a follow-up fix commit and rebuild again.
