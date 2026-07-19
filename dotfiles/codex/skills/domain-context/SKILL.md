---
name: domain-context
description: Use when planning, implementing, reviewing, debugging, or writing workflow artifacts in a repo with docs/agents/domain.md, CONTEXT.md, CONTEXT-MAP.md, ADRs, or behavior-affecting domain vocabulary.
---

# Domain Context

Use project domain context as a global invariant for coding work. This skill consumes existing domain language; it only changes the domain model through `domain-modeling` when the current task is already about resolving terminology or design meaning.

## When Active

Use this skill when either is true:

- The repo has `docs/agents/domain.md`, `CONTEXT.md`, or `CONTEXT-MAP.md`.
- The current work introduces, changes, or depends on domain terms whose meaning affects behavior.

If neither is true, continue without creating domain docs.

## Read Existing Context

When active, read the repo's domain-doc instructions before finalizing work:

- Prefer `docs/agents/domain.md` when present.
- Use the relevant `CONTEXT.md` or `CONTEXT-MAP.md` vocabulary.
- Respect ADRs according to the repo's domain-doc instructions.

Completion criterion: the current work uses canonical domain terms and avoids known aliases.

## During Planning Or Spec Writing

Use canonical terms in task names, test names, interfaces, user-facing labels, specs, plans, PRDs, and issue briefs.

If planning or spec writing introduces, changes, or resolves domain terminology, use `domain-modeling` to capture the decision.

If the design and domain context disagree, pause before finalizing. Resolve from repo evidence if clear; otherwise ask one focused question.

Completion criterion: the artifact and domain context agree on the terms and relationships that affect behavior.

## During Implementation, Review, And Debugging

Treat domain context as read-only unless the task explicitly involves changing the domain model.

If implementation, review, or debugging reveals that the spec, plan, code, and domain context disagree, surface the mismatch instead of silently changing the glossary.

Use `domain-modeling` only when the current task is already about resolving terminology or design meaning, or when the user asks you to resolve the ambiguity.

Completion criterion: the code, tests, review findings, and debugging conclusions use canonical terms and identify unresolved domain mismatches clearly.
