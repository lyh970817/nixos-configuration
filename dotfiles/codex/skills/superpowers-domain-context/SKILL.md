---
name: superpowers-domain-context
description: Use when Superpowers specs or plans must apply project domain context to docs/superpowers artifacts.
---

# Superpowers Domain Context

Apply project domain context to Superpowers artifacts.

This is a Superpowers-only companion to `domain-context`. `domain-context` owns the general rules for reading domain docs, using canonical terms, invoking `domain-modeling`, and surfacing mismatches. This skill only adds checkpoints for Superpowers specs and plans.

## When Active

Use this skill when the current Superpowers work writes or finalizes either artifact type:

- `docs/superpowers/specs/...`
- `docs/superpowers/plans/...`

If neither is true, use `domain-context` directly when its activation rules apply.

## First Apply Domain Context

Before finalizing a Superpowers spec or plan, first apply `domain-context`.

Completion criterion: the artifact uses canonical domain terms, avoids known aliases, and identifies unresolved domain mismatches clearly.

## Before Finalizing A Superpowers Spec

Before writing or finalizing `docs/superpowers/specs/...`:

- Confirm the spec's problem statement, terms, entities, relationships, and acceptance criteria match the project domain context.
- If the spec introduces, changes, or resolves domain terminology, follow `domain-context` for whether to use `domain-modeling`.
- If the spec and domain context disagree, do not finalize the spec until the mismatch is surfaced or resolved.

Completion criterion: the spec and domain context agree on the terms and relationships that affect behavior.

## Before Writing A Superpowers Plan

Before writing `docs/superpowers/plans/...`:

- Use canonical terms in task names, test names, interfaces, and user-facing labels.
- If planning exposes an unresolved domain ambiguity, follow `domain-context` for whether to use `domain-modeling` or ask before changing docs.
- Add a short pointer in the plan's Global Constraints telling implementation agents where to read domain vocabulary.

Example:

```md
- Domain vocabulary: follow `docs/agents/domain.md` and use the relevant `CONTEXT.md` vocabulary when naming domain concepts, tests, interfaces, and user-facing labels.
```

Completion criterion: implementation agents can find the project domain context from the plan and avoid vocabulary drift.
