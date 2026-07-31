---
name: sync-omp-skills
description: Reconcile the declarative Oh My Pi skill set managed by this machine's Nix Home Manager configuration. Use when adding, removing, enabling, disabling, or auditing global OMP skills.
---

# Sync OMP Skills

OMP's global user skill set is declarative. The tracked source of truth is
`dotfiles/omp/skills/`, linked to `~/.omp/agent/skills` by
`home/programs/omp.nix`. OMP runtime state under `~/.omp/agent` remains
machine-local.

This workflow is OMP-specific. Do not use `npx skills`, edit Codex profiles,
or change `~/.codex/skills`, `~/.codex/shared-skills`, or `~/.agents` while
maintaining OMP skills.

## Workflow

1. Inspect `home/programs/omp.nix`, `dotfiles/omp/skills/`, and the effective
   OMP skill settings with `omp config get`.
2. Make the intended membership change in `dotfiles/omp/skills/`:
   - add an OMP-authored skill as `<name>/SKILL.md`;
   - link an intentionally shared skill from its tracked source; or
   - remove the link for a skill OMP must not expose.
3. Express source isolation and disabled installed skills in the OMP activation
   settings in `home/programs/omp.nix`. Keep Codex compatibility discovery off
   unless explicitly requested.
4. Do not mutate `~/.omp/agent/skills` directly. Home Manager owns that link.
5. Follow the Nix configuration repository policy: commit the scoped change,
   rebuild, then verify the effective configuration and resolved skill links.

## Invariants

- `~/.omp/agent/skills` resolves to the tracked `dotfiles/omp/skills` tree.
- OMP-native `SKILL.md` files are one directory below `skills/`.
- A disabled skill remains present only when intentional; record it through
  `skills.ignoredSkills` rather than an undocumented local workaround.
- Project-local Agent Skills are independent of this global OMP user skill set.
