---
name: setup-domain-docs
description: Set up a project's domain documentation for agents - a docs/agents/domain.md consumer guide for CONTEXT.md and docs/adr/, and the pointer block in AGENTS.md. Invoked manually in a project that keeps a glossary or ADRs with domain-modeling.
disable-model-invocation: true
---

# Setup Domain Docs

Scaffold the consumer rules for a repo's domain documentation: where `CONTEXT.md` and ADRs live, and how agents read them. This is the domain-docs part of Matt Pocock's `setup-matt-pocock-skills`, and nothing else: no issue tracker, no triage labels, no other skills, no plugin install.

## Process

### 1. Explore

Read whatever exists; don't assume:

- `AGENTS.md` and `CLAUDE.md` at the repo root: does either exist? Is there already a `### Domain docs` block in either?
- `CONTEXT.md` and `CONTEXT-MAP.md` at the repo root
- `docs/adr/` and any `src/*/docs/adr/` directories
- `docs/agents/domain.md`: does this skill's prior output already exist?
- Monorepo signals: a `pnpm-workspace.yaml`, a `workspaces` field in `package.json`, or a populated `packages/*` with its own `src/`. Their absence means single-context, which is almost every repo.

### 2. Decide the layout

Default to **single-context** (one `CONTEXT.md` + `docs/adr/` at the repo root). This fits almost every repo; write it without asking. Offer **multi-context** (a root `CONTEXT-MAP.md` pointing to per-context `CONTEXT.md` files) only when exploration found monorepo signals; then confirm which layout they want.

### 3. Write `docs/agents/domain.md`

Copy [domain.md](./domain.md) from this skill folder to `docs/agents/domain.md`, creating `docs/agents/` if needed. If the file already exists, replace it with the template rather than merging; the user edits it afterwards if they want changes. Do not create `CONTEXT.md` or `docs/adr/`: `/domain-modeling` creates them lazily.

### 4. Add the pointer block

Edit `AGENTS.md` at the repo root, creating it if absent. If the project has only `CLAUDE.md`, add the block there instead and tell the user that is where it went; never create the second file alongside the first.

If a `### Domain docs` block already exists in the chosen file, replace its contents in place rather than appending a duplicate. Don't touch the surrounding sections. The block, with the layout filled in:

```markdown
### Domain docs

[one-line summary of layout: "single-context" or "multi-context"]. See `docs/agents/domain.md`.
```

When creating `AGENTS.md`, or when the file has no `## Agent skills` section, put the block under a new `## Agent skills` heading; otherwise place it inside the existing one.

### 5. Done

Tell the user the setup is complete: agents now read `docs/agents/domain.md` before exploring, and `/domain-modeling` maintains `CONTEXT.md` and `docs/adr/`. They can edit `docs/agents/domain.md` directly later; re-running this skill only resets it to the template.
