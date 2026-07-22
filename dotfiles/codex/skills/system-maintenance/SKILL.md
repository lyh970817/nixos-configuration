---
name: system-maintenance
description: System-wide and user-environment maintenance and configuration workflow for this machine. Use for tasks outside an individual project's source or project-local configuration, including NixOS or Home Manager changes, host packages, services, desktop and launcher configuration, rebuilds, declarative machine or user state, and mutable per-user runtime or configuration state. Use agent-config-setup instead for configuring Codex, Claude, Claude Code, AI agents, skills, skills.sh, profiles, plugins, launchers, or agent config directories.
---

# System Maintenance

Use `/home/andongni/.nixos-config` as the source of truth for this machine's NixOS and Home Manager configuration.

## Workflow

1. Establish the ownership boundary: determine whether the task belongs to an individual project's source or project-local configuration, declarative NixOS/Home Manager state, or mutable per-user runtime or configuration state. Use this skill for the latter two, and inspect the effective configuration and runtime paths before changing state. Completion criterion: the owning layer and a non-destructive maintenance path are identified.
2. Start in `/home/andongni/.nixos-config` and read the local guidance such as `AGENTS.md` before editing. Completion criterion: the relevant repo rules and current file layout are known.
3. Make scoped configuration changes in the existing NixOS/Home Manager structure or mutable per-user runtime structure. Completion criterion: only files needed for the requested maintenance task are changed.
4. If applying the NixOS/Home Manager configuration is needed, rebuild from that repo with `sudo nixos-rebuild switch --flake .#andongni --impure`. Completion criterion: the rebuild command is run from `/home/andongni/.nixos-config`, or the user is told why it was not run.

## Rebuild Discipline

For configuration changes in this repo, follow the repository rebuild policy: commit the scoped change first so the configured pre-commit hooks run verification, then apply the committed configuration with `sudo nixos-rebuild switch --flake .#andongni --impure`. If the rebuild fails, make a follow-up fix commit and rebuild again.
