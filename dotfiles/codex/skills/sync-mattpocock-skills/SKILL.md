---
name: sync-mattpocock-skills
description: Synchronize the shared global agent skill set from mattpocock/skills, including pruning skills removed upstream while keeping Claude Code independent. Use when the user wants to synchronize that managed set or when system-maintenance routes Matt Pocock skill maintenance.
---

# Sync Matt Pocock Skills

Make the shared global installation owned by `mattpocock/skills` exactly match
the complete current *non-deprecated* upstream skill set for Codex,
Antigravity, Gemini CLI, and GitHub Copilot. A skill is deprecated when its
current upstream source path is under `skills/deprecated/`; never install or
retain such a skill, even if `npx skills@latest add mattpocock/skills` includes
it in its repository enumeration. Treat Codex profile membership as a separate
concern, except for preserving the base-profile isolation described below and
the `domain-modeling` exception. Claude Code is outside this shared set and
must use an independent skill tree.

Matt Pocock publishes one portable skill source rather than separate Codex and
Claude editions. Follow upstream's recommended `npx skills@latest add
mattpocock/skills` flow and target Codex explicitly. On this machine,
the `npx skills@latest` CLI reuses the existing universal `/home/andongni/.agents/skills` copy
for Codex and the other universal consumers; it installs a separate copy for
the non-universal `claude-code` target.

Whether the installed CLI calls the operation `install` or `add`, its
installation command must explicitly select only the intended non-Claude
shared-set agents. Never select, pass to `--agent`, or otherwise install for
the `Other` agent/target; deselect `Other` if the CLI presents it interactively.

Use the `npx skills@latest` CLI. Do not implement synchronization by directly
deleting or copying managed skill folders or by editing
`/home/andongni/.local/state/skills/.skill-lock.json`.

## 1. Preflight

1. Read `/home/andongni/.local/state/skills/.skill-lock.json` and list every
   installed skill whose `source` is exactly `mattpocock/skills`. Record this
   pre-sync manifest.
2. Run non-mutating `npx skills@latest` inspection commands to enumerate the complete
current `mattpocock/skills` repository and the global Codex installation. Record
each upstream skill's source path, split the enumeration into maintained and
deprecated names, and treat only the maintained name set as installable.
   Do not probe help for a subcommand by appending `--help`: this CLI may execute
   the subcommand instead. Completion criterion: the upstream name set and the
   installed source-owned name set are both known.
3. Confirm that the upstream repository is reachable and that enumeration
   completed successfully before proposing any removal.
4. Detect every maintained upstream name already occupied by a skill whose lock-file
   source is not `mattpocock/skills`, or by an unmanaged local skill folder.
   Stop without changing state and report every conflicting name and owner if
   any collision exists.
5. Inspect CLI discovery metadata, agent registrations, filesystem links, and
   actual configured paths for the
   source-owned skills. Preserve the existing shared-set membership for Codex,
   Antigravity, Gemini CLI, and GitHub Copilot. If another non-Claude consumer
   exists, report it in the plan and preserve its registration unless the user
   explicitly decides otherwise. Resolve and record the exact CLI identifiers
   accepted by `npx skills@latest --agent`; do not assume its `Agents` display
   labels prove runtime path selection or are valid command arguments.
6. Search every `/home/andongni/.config/claude*/skills` tree for a symlink or
   path that resolves into `/home/andongni/.agents/skills`. Claude Code must not
   consume the shared set. If any such link exists, stop before synchronization
   and report that Claude must first be migrated to independent skill copies;
   never replace the links with Codex-format copies as part of this workflow.
   If no shared link exists, record a lightweight manifest of every Claude skill
   path, file type, and resolved target for post-sync comparison.

## 2. Plan and Approval

Compute a concise plan showing:

- all existing `mattpocock/skills` installations to remove;
- all current non-deprecated upstream skills to install;
- all deprecated upstream names that will be removed and will not be reinstalled;
- newly published names that will appear;
- stale Codex profile entries that will be removed;
- base-profile disables that will be added; and
- all non-Claude shared skill-store consumers that will observe updated
  contents; and
- the exact resolved `npx skills@latest remove` and `npx skills@latest add` commands,
  including normalized manager agent identifiers and an explicit omission of
  the `Other` agent/target from the installation command.

Request one explicit confirmation after showing the complete plan. Make no
mutation before that confirmation. Once confirmed, finish routine removal,
installation, profile reconciliation, and verification without asking again.

## 3. Replace the Managed Set

1. Remove every existing global registration owned by `mattpocock/skills`
   through `npx skills@latest remove`, passing the complete recorded name set, global
   scope, every registered non-Claude shared-set agent, and non-interactive
   confirmation.
   Completion criterion: every recorded pre-sync Matt Pocock registration has
   been removed for the shared set and no Claude registration or configuration
   changed.
2. Reinstall every current non-deprecated skill through `npx skills@latest add
`mattpocock/skills`, using global scope, all recorded non-Claude shared-set
agents except `Other`, the explicit maintained-name list (never `--skill '*'`
when that would include a deprecated skill), `--copy`, and non-interactive
confirmation. Explicitly omit `Other` from `--agent` arguments; if this CLI
version presents agent choices interactively, leave `Other` unselected.
   Completion criterion: every enumerated non-deprecated upstream name is
installed for the shared set and attributed to `mattpocock/skills` by the
manager; no deprecated upstream skill is installed.
3. If installation fails, retry the failed manager operation once. If it still
   fails, stop. Do not restore folders or lock entries manually. Report the
   pre-sync manifest, the current installed set, missing and stale names, and
   exact manager commands for recovery.

The clean replacement, rather than `npx skills@latest update`, is intentional:
in-place update refreshes known skills but does not establish that upstream-
deleted skills have been removed or newly published skills have been added.

## 4. Reconcile Codex Profiles

After a successful reinstall, inspect `/home/andongni/.codex/config.toml` and
every `/home/andongni/.codex/*.config.toml` profile.

1. Remove `[[skills.config]]` entries that refer by name or path to a deprecated
   Matt Pocock skill from every Codex profile. Preserve unrelated entries and
   surrounding configuration.
2. In `/home/andongni/.codex/config.toml`, ensure every currently installed
   non-deprecated Matt Pocock skill other than `domain-modeling` has a name-based
   `[[skills.config]]` entry with `enabled = false`. Replace any base-profile
   enable for those skills; the user configures their membership separately.
3. `domain-modeling` is the explicit exception: ensure it has a name-based
   `[[skills.config]]` entry with `enabled = true` in the base profile and in
   every named Codex profile. Replace any path-based `domain-modeling` entry
   with this name-based enable. Do this only while `domain-modeling` remains a
   non-deprecated current upstream skill.
4. Do not add any other newly published skills to named profiles. Do not
   otherwise change which skills named profiles enable; the user configures
   those memberships separately.
5. Do not edit `/home/andongni/.config/claude*`. Do not add Claude Code as a
   manager target or permit Claude skill paths to resolve into the shared
   `/home/andongni/.agents/skills` tree.

Completion criterion: no Codex profile points at a deprecated Matt Pocock
skill, every installed non-deprecated member other than `domain-modeling` is
isolated from accidental base-profile auto-discovery, `domain-modeling` is
enabled in every Codex profile, every edited TOML file parses successfully,
and named-profile membership has not otherwise changed except for that required
`domain-modeling` enable.

## 5. Verify

Re-enumerate upstream, the manager lock, installed paths, agent registrations,
and Codex profile entries. Verify all of the following:

- installed names owned by `mattpocock/skills` exactly equal current
  non-deprecated upstream names;
- every installed member has `source = "mattpocock/skills"` in the manager lock;
- no deprecated directory, manager entry, or Codex profile reference remains;
- every installed member other than `domain-modeling` is disabled in the base
  profile, while `domain-modeling` is enabled in every Codex profile;
- the non-Claude shared-set registrations were restored exactly;
- no Claude configuration directory, registration, or resolved skill path uses
  the shared set; and
- the post-sync Claude skill-path manifest exactly equals its pre-sync manifest.

Report the removed, installed, newly added, deprecated, and profile-reconciled
names, plus the verification evidence. This workflow changes mutable Codex
state and does not require a NixOS rebuild.
