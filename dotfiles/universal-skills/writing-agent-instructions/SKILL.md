---
name: writing-agent-instructions
description: Use when authoring or revising a file that instructs an agent — a SKILL.md, a rules file, AGENTS.md or CLAUDE.md, or an agent system prompt — and the question is what to put in it, what to cut, and where a rule belongs. Not for one-off subagent prompts, handoff briefings, todo files, or documentation.
---

# Writing agent instructions

Include a line only if the agent behaves differently with it than without it.
Everything else is context you pay for every turn and get nothing back.

## Cut

- If the agent already does it by default, the line buys nothing.
- Don't defend a rule against misreadings. State it and stop. A guard clause
  spends its words on what might go wrong instead of on what to do; let the rare
  misreading happen and fix it when it does.
- Don't restate code, commands, or structure; it rots when they change — point
  at the file. A finding or measurement stays true: state it inline.
- Numeric caps buy obedience, not the behaviour you wanted: the model that
  honours "under 200 words" is not the one you were writing for, and the model
  that ignores it is unaffected. Take brevity from structure instead — named
  sections, one item per line.

## Keep

Constraints against irreversible harm — secrets, connectivity, bootability,
anything with no undo. These are not defensive; without them the agent does the
wrong thing rather than merely says it badly. State each once, tersely, with the
recovery path. The mihomo and security sections of this repo's `AGENTS.md` are
the shape.

Contracts the agent cannot infer — a return format, a branch naming protocol, a
name only you use. There is no default to fall back on.

## Move rather than delete

Every rule has one owner. A rule that is true but misplaced moves to the file
that owns it; deleting it is a different act with a different result. Prose a
mechanism can enforce — a hook, a wrapper, a generated file — moves into the
mechanism. Never say the same thing in two files; you will edit one of them.

## Name what you cut

Trimming has a floor you will not see — a regression surfaces sessions later, to
the user. Cut anyway, git holds the restore, but name the cut in your report.

## Descriptions

A skill's `description` decides when it fires. Write it as narrowly as the
situation allows and prefer a miss to a spurious trigger. Name the concrete
artefacts that should trigger it, and add an explicit non-trigger list when the
subject is broad enough that half the repo could be argued into it.
