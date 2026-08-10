# FirstMate's reporting architecture

## Why this file exists

The Stop-hook rewriter in this repo (`dotfiles/claude/response-simplifier.md`)
borrows its shape from FirstMate, an unrelated project by another author. Several
sessions have re-derived that shape from scratch, and at least one of them got it
wrong in a way that changed the design. This file records what FirstMate actually
does, what was deliberately taken from it, what was deliberately rejected, and
the measurements behind those choices, so the next session can start from here.

Everything about FirstMate below was read directly from the local checkout at
`/home/andongni/home/firstmate` — the home desktop's home directory, reachable on
the laptop over SSHFS at `~/home` — at commit `7d437ab`. Upstream is
`github.com/kunchenguid/firstmate`. Line references are to that commit.

### Relationship to `stop-hook-model-comparison.md`

[`stop-hook-model-comparison.md`](stop-hook-model-comparison.md) is about a
**different hook**. It documents the **Codex** Stop hook
(`dotfiles/codex/hooks/response-simplifier.sh` +
`dotfiles/codex/response-simplifier.md`), which leaves the original response in
place and appends a compact `**First Mate**` brief of at most 120 words, using
`gpt-5.4` at medium effort. That doc owns the model comparison and the
brief-versus-rewrite argument for that hook.

This file is about the **Claude** Stop hook
(`dotfiles/claude/hooks/response-simplifier.sh` +
`dotfiles/claude/response-simplifier.md`), wired as `Stop` in
`dotfiles/claude/settings.json`, which produces a full sectioned rewrite plus a
trailing summary using `claude-sonnet-5`. The two hooks share a name, a
1,500-character gate, and a fail-open posture, and nothing else. Do not carry a
conclusion from one to the other without re-checking it.

## What FirstMate is, and where its prompt lives

FirstMate is a fleet-supervisor agent: the user is the "captain", FirstMate is
the only point of contact, and all project work is delegated to spawned
"crewmates". Its prompt is not a config file — it is the repo.

- `AGENTS.md` (~60 KB, 14 numbered sections) is always loaded. `AGENTS.md:5`:
  "This file is your entire job description." `CLAUDE.md` is a symlink to it.
- `.agents/skills/*/SKILL.md` — 19 skills at this commit — are loaded **at their
  triggers**, not all at once. `.claude/skills` symlinks to `.agents/skills`.
  `AGENTS.md` §13 lists the agent-only ones with an explicit "load before X"
  condition for each; the rest are `user-invocable` slash commands.
- `bin/` scripts and `docs/` are authoritative for mechanics but are read on
  demand, not resident in the prompt.

That split matters for what follows: the always-loaded part carries etiquette and
safety, and the per-situation output shapes live in skills.

## The correction: the four sections belong to `/bearings`, not to FirstMate

`Captain's Call`, `Recently Landed`, `Underway`, `Charted Next` are **the
`/bearings` skill's chat-digest contract**, defined in
`.agents/skills/bearings/SKILL.md`. They are **not** FirstMate's universal output
style. An earlier round of research on this exact question concluded they were,
and that belief is what this file mainly exists to correct.

The skill says so itself, at `bearings/SKILL.md:69`:

> This skill is the one owner of the `/bearings` chat-response format; the
> snapshot and classifier own the data that feeds it, and no other file restates
> this contract.

Corroborating evidence that the ownership is real and enforced:

- `bearings/SKILL.md:70`: "Every `/bearings` chat response renders EXACTLY these
  four sections, in THIS order, and nothing else structural (there is no At
  Anchor section)." The scope of the rule is `/bearings` responses, not
  responses.
- `ahoy/SKILL.md:26-27` — `/ahoy`, the session-recap command — says "Bearings
  alone owns its gathering, artifact, and response contract. Do not restate that
  contract or combine a session recap with Bearings output." A sibling skill is
  explicitly forbidden from reusing the four sections.
- A repo-wide grep for the section names finds them in exactly three files:
  `bearings/SKILL.md`, and two places that *refer* to Captain's Call as a
  Bearings section (`decision-hold-lifecycle/SKILL.md:24,34` and
  `docs/decision-hold-lifecycle.md:73`). `AGENTS.md` never mentions them.

### What the contract actually says

Four sections, always in this order, each **always rendered even when empty**,
each with a fixed empty-state sentence (`bearings/SKILL.md:72-83`):

| Section | Holds | Empty-state sentence |
| --- | --- | --- |
| `Captain's Call` | only what needs the captain's own action now | "Nothing needs your action right now." |
| `Recently Landed` | the bounded current recent-completions baseline | "No recent completions are in the current baseline." |
| `Underway` | live work progressing on its own, one line each | "Nothing is underway." |
| `Charted Next` | queued or gated work, plus action-free integrity warnings | "Nothing is queued." |

The buckets are declared **mutually exclusive**, with the routing rule spelled
out (`bearings/SKILL.md:86`):

> The four buckets are mutually exclusive, so every item is forced into exactly
> one: needs-your-action is Captain's Call, done is Recently Landed,
> self-progressing is Underway, and not-yet-started work or an action-free
> fleet-integrity warning is Charted Next.

A further rule (`:87`) exists purely to keep `Captain's Call` from silting up —
working or validating tasks, blocked or date-gated items, landed work, completed
scouts' report pointers, declared external waits, and bare recorded PRs "each
belong to one of the other three sections, never Captain's Call". The
action-needed bucket is defended, not just defined.

Each digest is also "a complete current snapshot, never a delta against a prior
report" (`:84`).

### The same grouping at two levels of detail

FirstMate already renders this one grouping at two depths, and the choice is a
mode, not a different format:

- Plain `/bearings` returns "only the concise four-section chat digest"
  (`:15`) and writes nothing.
- `/bearings file` writes `data/status-report-<YYYY-MM-DD>.md` and *then* returns
  the same digest with a link to it (`:16`, `:64`).

The report is not a substitute for the digest — file mode produces **both**. And
the report is the same shape, not a different one (`:53`): "The report uses the
same four complete sections as the chat, in the same order, and adds the detail
the chat omits."

The depth relationship is stated explicitly (`:93`):

> Detailed decisions, plans, full gate reasons, and evidence belong in the file
> only when file mode is explicit, so plain chat stays concise and file-mode chat
> stays materially shorter than that file.

So: one grouping, two depths, both emitted together, the short one never omitted.
That is the same structure as this repo's rewriter emitting a full sectioned body
and a trailing `**Summary**`.

## `AGENTS.md` §9 — "Escalation and captain etiquette"

§9 (`AGENTS.md:402-445`) is the always-loaded etiquette layer, and it is what the
`/bearings` contract defers to for tone (`bearings/SKILL.md:92`: "The chat
follows `AGENTS.md` section 9 and carries one scannable line per item").

Its opening rule, in bold, is:

> **Talk in outcomes, not mechanics.**
> Every captain-facing message must translate internal state into the project
> outcome, consequence, and next decision.

**Correction to a common paraphrase:** the list that follows that rule is
primarily a **translation table**, not a licensed-to-drop list. Roughly a dozen
entries map an internal label to captain-facing phrasing — `teardown` → cleanup;
`worktree`/`checkout` → local copy; `wake`/`watcher`/`heartbeat`/`stale` →
notification, monitoring, waiting too long, stopped responding; `brief` →
instructions; `fail-closed` → "stops safely when something goes wrong";
`fail-open` → "steps aside and lets work continue when the check cannot
complete". The instruction is to *rewrite* these terms before sending, not to
discard the facts they carry.

There **is** a drop list, but it is separate and much shorter (`AGENTS.md:440`):
"Do not surface automatic fixes, retries, routine progress, or internal
supervision mechanics." Plus a related ban (`:423`): never relay worker reports,
status lines, tool output, or decision records verbatim — read them as evidence
and send the outcome.

The distinction is load-bearing for our rewriter. "Translate the mechanic into
its outcome" and "delete the mechanic" produce different rewrites, and only the
first preserves the information.

§9 also fixes the escalation shape: "Lead directly with concrete evidence, then
the consequence, options when applicable, and a recommendation" (`:428`) — which
is a *deliberation* shape, distinct from the four-section status shape, and is
the seed of the open question recorded in `todo.md`.

## Dead end: "calm mode" is not related

`calm` is a **Pi-only presentation toggle** (`docs/calm.md`,
`.pi/extensions/fm-calm.ts`). It hides Pi's `Working...` row and draws a small
animated boat, hides collapsed thinking labels and built-in tool shells, and
nothing else. `docs/calm.md` is explicit: "Calm changes presentation only. Tool
execution, input delivery, ordering, model context, session storage, diagnostics,
and `/export` and `/share` operation remain unchanged." It has no bearing on
response format or content. Recorded here so nobody investigates it again.

## The architectural implication

This is the reusable insight, and the reason the correction above matters:

**FirstMate's pattern is a small set of named contracts, each owned by exactly
one skill, with one selected per situation — not one universal output format.**

`/bearings` is one contract among several. `/ahoy` is another (a session-history
recap over a bounded interval, no fixed sections, forbidden from mixing with
Bearings). `fmx-respond` is a third (public-facing voice, "aim for a single
message, two at the very most"). What is universal is only the thin etiquette
layer in `AGENTS.md` §9 — address, outcomes-not-mechanics, evidence-first
escalation — plus the safety rules. The *shapes* are per-situation and each has
a single declared owner and a stated non-overlap with its siblings.

Ownership is enforced by prose invariants: one owner per contract, no restating
it elsewhere, no combining two contracts in one response. That is what keeps
selection tractable — there is never a question of which file to obey, only which
situation applies.

## Decisions already taken for this repo's rewriter

Target files, for reference only — an agent may be actively retuning them, so
treat the files as authoritative over this summary:
`dotfiles/claude/response-simplifier.md` (the prompt) and
`dotfiles/claude/hooks/response-simplifier.sh` (the driver).

### Rejected: the nautical vocabulary

No `Captain's Call`, no `Charted Next`, no maritime register. Plain literal
section names instead. As of this writing the prompt uses three: `## Your call`,
`## What happened`, `## Watch out`.

### Kept: the grouping discipline

- Mutually exclusive buckets; every item lands in exactly one and appears once.
- Every section renders even when empty, each with a fixed one-line empty state.
- Outcomes, not mechanics.
- One grouping at two levels of detail — the full sectioned body plus a short
  trailing `**Summary**`, both emitted every time, mirroring FirstMate's digest
  + report.

Observed mapping, for orientation rather than as a rule: `Your call` corresponds
to `Captain's Call`; `What happened` absorbs both `Recently Landed` and
`Underway`; `Watch out` has no FirstMate counterpart; nothing corresponds to
`Charted Next` (queued-but-not-started work currently has no dedicated home).

### Kept anyway: `Watch out` is first-class

`Watch out` is confirmed by the user from reading a live rewrite, and it is kept
even though FirstMate has no counterpart for it. Caveats, scope limits, untested
paths, risks, work still running, and unverified claims live there. The rule that
gives it teeth: **a claim whose limit will not fit is dropped whole rather than
stated unqualified.** An unhedged claim is worse than a missing one.

### Rejected: any length limit on the long rewrite

There is **no cap on the rewrite body at all**. The user wants it to unpack.
Only the summary is constrained (currently at most four short lines).

Consequence to record, because it retires an earlier argument: the reasoning that
"the section frame costs roughly 120 words, so short inputs cannot compress" is
**dead**. Compression is no longer a goal, so frame overhead is not a cost to
weigh. `min_chars=1500` in the hook survives, but it is now justified by a
*different* question — is restructuring **useful** on a message this short? — not
by compression economics. The hook's own comment has already been updated to that
justification.

## Measurements

These are measurements from this repo's own experiments, with the sample sizes
stated. They are not guarantees, and they are not verifiable from either
checkout — they are recorded here as reported so they are not re-run blindly.

### Similarity to input, and body length as a fraction of input

| Prompt / model | Similarity | Body length |
| --- | --- | --- |
| Original preservation prompt | 0.79 | 97% |
| Sectioned prompt, Haiku | 0.19 | 55% |
| Sectioned prompt, Sonnet 5 | 0.36 | 94% |
| Cap-free prompt, Sonnet 5 | 0.40 | 125% (148% including the summary) |

### Blind retention findings, n=31, seven categories

| Configuration | Total findings | Major |
| --- | --- | --- |
| Haiku | 44 | 9 |
| Sonnet 5, capped prompt | 10 | 2 |
| Sonnet 5, cap-free | 3 | 0 |

### The interpretation that matters

**The compression was the model obeying the cap, not the prompt working.** Sonnet
5 with the *same* capped prompt ignored the cap and returned 94% of input length,
where Haiku returned 55%. The 55% was a Haiku behaviour, not a prompt property.

And removing the cap did **not** regress toward copying: similarity went 0.36 →
0.40 while retention findings went 10/2 → 3/0. Letting the model expand bought
retention without buying paraphrase-level fidelity to the source.

### Mechanical token retention is a useless gate

Mechanical token retention measured **100% for all four models tested** — and one
of those models still inverted a running job into a finished one. A gate that
every candidate passes while a status inversion slips through is not a gate.

That is why the retention judge scores **status inversion, agency reversal, mood,
negation, conditionality, hedge strength, and topic coverage** instead. Those
seven categories are the same seven the current prompt's "Do not flip the
meaning" section drills against, minus topic coverage, which the "cover every
topic" rule handles separately.

### One discrepancy to reconcile

The hook script's own comment cites **41** real messages from this project for
the length measurement (101-162% of original at every input size, against the
previous Haiku setup's 55%), while the blind retention run above is **n=31**.
These are probably different corpora or different rounds, but nothing in either
checkout says so. Reconcile before quoting either number as "the" sample.

## Open question

Whether the rewriter should carry **two** contracts — a status/digest shape and a
deliberation shape — and whether selecting between them is reliable enough to be
worth it. Recorded as an item in [`../todo.md`](../todo.md).
