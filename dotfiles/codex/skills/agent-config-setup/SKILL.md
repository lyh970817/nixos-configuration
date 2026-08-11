---
name: agent-config-setup
description: Configuration workflow for Codex, its config directory (~/.codex), skills, profiles, or launchers on this machine. Not for other NixOS/Home Manager, host package, service, desktop, or launcher work.
---

# Agent Configuration (Codex)

## Model

The tracked sources of truth are `/home/andongni/.nixos-config/dotfiles/codex/` for the Codex-authored skills and `/home/andongni/.nixos-config/dotfiles/universal-skills/` for the five universal skills (`bro`, `domain-context`, `nix-environment-setup`, `r-dev-shell`, and `visual-verification`), plus `dotfiles/agents/skills` for the separate Matt Pocock-managed shared pool. Home Manager module `home/programs/mutable-configs.nix` wires it into `~/.codex` mostly via `mkOutOfStoreSymlink` — an out-of-store symlink pointing at this repo checkout (`osConfig.portable.configDir`) instead of a store copy. **Edits to symlinked files are live immediately; no rebuild needed.**

- Symlinked: `AGENTS.md`, `rules/`, `hooks.json`, the response-simplifier hook, the shared response-simplifier prompt, custom agents under `agents/`, five Codex-authored skill entries (`agent-config-setup`, `sync-mattpocock-skills`, `codex-dynamic-workflows`, `commit-guidelines`, `session-handoff`), and five universal bridge entries (`bro`, `domain-context`, `nix-environment-setup`, `r-dev-shell`, `visual-verification`). Codex-authored files are sourced from `dotfiles/codex/`; the response prompt is shared from `dotfiles/claude/response-simplifier.md`; the five universal bridges are sourced from `dotfiles/universal-skills/`.
- Copied, not linked: every named profile, including `orchestrator`. `home.activation.codexPolicy` seeds each 0600 ordinary file from `dotfiles/codex/profiles/*.config.toml`, then reconciles owned fields into `~/.codex/<name>.config.toml` on every activation. This lets relative skill paths resolve from `~/.codex` while Codex retains hooks and other mutable or unknown runtime state. For `orchestrator`, the authored root policy and `features.multi_agent_v2` fields are owned; hooks remain runtime state. Editing a copied runtime profile directly is not durable for owned fields; edit its tracked template instead and rebuild.
- `~/.codex/shared-skills` is a separate out-of-store symlink to `dotfiles/agents/skills` — a Matt Pocock-managed, curated, shared 36-skill pool used across profiles, not Codex-specific or universal. It must not be linked into Claude. It's CLI-only: Codex Desktop's `CODEX_HOME` is `~/.codex-desktop`, which never reads `~/.codex`, so Desktop never sees this symlink.
- Mutable, not sourced from the repo, not configuration to manage here: `config.toml` (base config), `auth.json`, sqlite state, `history.jsonl`, `sessions/`, shell snapshots, caches.

## Skill discovery and policy

The CLI auto-discovers system skills shipped under `$CODEX_HOME/skills/.system` and the skill entries installed under `$CODEX_HOME/skills`; profile selection is not a general allow-list. `$HOME/.agents/skills` is also a USER-scope source independent of `CODEX_HOME`. It must never exist on this machine — anything placed there auto-loads into every Codex surface, including Desktop, with no per-skill opt-out. The shared pool instead lives at `dotfiles/agents/skills`, reached only via `~/.codex/shared-skills`.

`home.activation.codexPolicy` preserves unknown user state while reconciling its owned base fields in `~/.codex/config.toml` before all five CLI profiles are selected. `features.remote_plugin = false` is the primary barrier for remote plugins. As a durable exception, it writes exact disabled `[[skills.config]]` names for bundled `imagegen` and `plugin-creator`, the five Google Drive skills, the browser/sites/visualization/deep-research skills, and the 20 exact `openai-templates:artifact-template-*` manifest names currently cached by the OpenAI templates plugin. It also explicitly enables bundled `openai-docs`, `skill-creator`, and `skill-installer`; hidden `review-agent` remains unmanaged. Codex Desktop is isolated at `~/.codex-desktop`, so it receives none of this CLI policy.

Profiles use `[[skills.config]]` stanzas only for targeted overrides. A path in such a stanza is resolved relative to the profile file's own runtime location under `~/.codex`:

- `skills/<name>` resolves to `~/.codex/skills/<name>` (from `dotfiles/codex/skills/`; only the five universal bridge names resolve to canonical sources in `dotfiles/universal-skills/`).
- `shared-skills/<name>` resolves to `~/.codex/shared-skills/<name>` (from `dotfiles/agents/skills/`, the shared pool).

Select a profile with `codex --profile <name>`. To add a targeted profile override, edit the profile's `[[skills.config]]` stanzas in `dotfiles/codex/profiles/<name>.config.toml`.

For synchronizing the whole Matt Pocock skill set, see the `sync-mattpocock-skills` skill (`dotfiles/codex/skills/sync-mattpocock-skills`) — it is a plain git-tracked Codex skill, not an externally managed install flow.

## Launcher and package

- CLI package derivation: `pkgs/codex.nix`; the CLI runs directly against `~/.codex` (`home/programs/codex-desktop.nix` adds `pkgs.codex` to `home.packages`). Shell alias `cdy` runs `codex --yolo`; `cdo` runs the high-effort `orchestrator` profile with `--yolo`.
- The `orchestrator` profile uses multi-agent V2 with 16 total resident threads (the root plus up to 15 subagents) and no depth ceiling. It disables the default collaboration-mode instruction so the profile's root instructions govern, and replaces inherited root instructions in subagents with `features.multi_agent_v2.subagent_developer_instructions`.
- Codex Desktop (GUI) is wired through the same `home/programs/codex-desktop.nix` via `programs.codexDesktopLinux`, using `pkgs.codex-desktop-isolated` (`pkgs/codex-desktop-isolated.nix`), which wraps the desktop app to keep its state under `~/.codex-desktop`/isolated XDG dirs instead of `~/.codex`, so it does not share state with the CLI.

## Workflow

1. Locate the tracked source under `dotfiles/codex/` for the Codex-authored skills, `dotfiles/universal-skills/` for the five universal skills, or `dotfiles/agents/skills` for the separate Matt Pocock-managed shared pool first; edit there, never a runtime copy under `~/.codex`.
2. Keep edits scoped to the requested change.
3. Commit the change so the repo's pre-commit hooks are the verification gate (repo policy) — do this even for changes that are already live via symlink.
4. Rebuild with `sudo nixos-rebuild switch --flake .#system --impure` (or the `rebuild` alias, which targets `/etc/nixos#system` and works from any directory) only when the change touches a copied profile (`dotfiles/codex/profiles/*.config.toml`) or Nix wiring itself (`mutable-configs.nix`, `codex-desktop.nix`, `pkgs/codex.nix`, `pkgs/codex-desktop-isolated.nix`). Pure content edits to runtime-linked files (`AGENTS.md`, `rules/`, the five universal bridges, `dotfiles/agents/skills/`, and the Codex-authored `dotfiles/codex/skills/`) are already live — commit only, no rebuild required.
