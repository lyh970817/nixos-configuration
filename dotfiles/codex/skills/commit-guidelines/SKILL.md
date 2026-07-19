---
name: commit-guidelines
description: Guidance for creating clear git commit history in Codex-managed workspaces. Use when the user asks Codex to commit changes, create commits, prepare a branch history, finish work with git commits, or otherwise run git commit after modifying files.
---

# Commit Guidelines

## Core Rules

- Commit only when the user has asked for commits or the current task explicitly includes committing.
- Use multiple commits to represent incremental and logical changes whenever committing changes.
- Write commit messages for the user-facing purpose of the change, not for reviewer-only or implementation-internal details.

## Commit Workflow

1. Inspect the worktree before committing with `git status --short` and, when useful, `git diff`.
2. Separate unrelated user changes from your own changes. Do not include user changes unless the user explicitly asked for them to be committed.
3. Group changes into logical commits that tell the story of the work:
   - Setup or scaffolding before implementation.
   - Implementation before tests or docs when those are meaningful separate steps.
   - Independent features, fixes, or migrations in separate commits.
4. Avoid artificial splits that make history harder to understand. If the whole diff is truly one atomic change, make the smallest honest history, but first look for natural boundaries.
5. Verify what will be committed before each commit, especially when using pathspecs or partial staging.

## Message Style

Use concise messages that describe what the user gains or what behavior changed.

Good:

- `Add profile-level commit guidelines skill`
- `Enable commit guidelines across profiles`
- `Remove commit policy from global instructions`

Avoid:

- `WIP`
- `Fix stuff`
- `Refactor commit code because tests needed mocking`
- `Address reviewer comments`
- Messages that mention Codex, agent internals, or implementation trivia unless those are the user-visible subject of the change.
