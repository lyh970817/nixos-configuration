# Stop-hook First Mate model comparison

## Current decision

Use `gpt-5.4` at `medium` reasoning effort with Prompt H. The hook leaves the
finished assistant response unchanged and adds only a compact `**First Mate**`
brief as the system message below it. The original remains visible and
authoritative; the brief is orientation, not a replacement report.

Prompt H has SHA-256
`ea14bc7ac6ff2d0264bde337a60aed81ba722812bc7ca8ef5ae9e800b286369e`.
It permits one to four bullets and at most 120 words, requires the outcome,
the highest-impact boundary, and each outstanding reader action or choice, and
keeps recommendations with different conditions separate.

The production guardrails are unchanged: the hook acts only at 1,500 or more
characters, has a 120-second timeout, invokes an ephemeral read-only child
with hooks disabled, and fails open.

## Why this is a brief, not a full rewrite

The stop hook's `systemMessage` appears below the original completed response.
The reader can already inspect that original, so a second long report creates
duplication rather than better communication. The full-body experiments below
were either near-copy edits of already strong originals or introduced retention
losses. A short companion brief gives the reader an outcome-first orientation
without hiding the source evidence, commands, caveats, or detailed reasoning.

This does not make the brief complete. It may selectively omit lower-priority
background while the original remains directly above it. The brief must not
distort conditions, ownership, scope, or safety boundaries.

## Community research context

A `last30days` v3.18.4 run on 2026-08-10 gathered 139 items: 16 Reddit
threads, 26 X posts, 7 YouTube videos with transcripts, 16 TikToks, 5
Instagram reels, 32 Hacker News stories, 13 GitHub items, 23 Digg clusters,
and 1 Techmeme headline. Reddit coverage was partial after HTTP 429 responses.
The directly ranked clusters were weakly focused on communication style, so the
synthesis also used web supplements and an earlier focused Opus 5 artifact.

The research provided candidates, not a model-quality measurement:

- GPT-5.4 was often described as warmer, more vivid, and more conversational,
  with a counter-warning that it can sound better while thinking worse.
- GPT-5.6 criticism centered on over-engineering, stale constraints,
  unnecessary elaboration, and exceeding the request; Terra-specific evidence
  was thin and mixed.
- GPT-5.5 had little recent preference evidence. Luna had almost no
  family-specific communication evidence and initially served as the speed
  baseline.
- GPT-4o and GPT-5.1 still received praise for natural conversation but were
  unavailable in the local Codex cache. Claude Opus 5 received both depth
  praise and criticism for verbosity, jargon, argumentativeness, and buried
  conclusions.

This is self-selected evidence across mixed tasks. It cannot estimate how
prevalent any opinion is and did not determine the production selection.

## Historical full-body phases

All full-body phases used 15 technical responses from this repository with
human-auditable checklists. Calls used Codex CLI 0.147.0, an ephemeral
read-only child, disabled hooks/user configuration, a common `<message>`
envelope, and a 120-second timeout. Blind judges saw opaque candidates, not
model or prompt identity.

| Phase | Matrix | Result | Why it was not the final design |
| --- | --- | --- | --- |
| 0 | 5 models/prompts × 15 | Luna low/revised was selected for safety | later audit found it expanded all 15 outputs and produced no requested summary |
| 1 | Control + 6 cells × 15 | Luna low/stronger-brief prompt passed retention | only `+1.13` mean body gain, `+1` median, no `+4` case; 8/15 material rewrites |
| 2 | Control + 6 cells × 15 | historical `**Summary**` contract recovered | every candidate failed retention, safety, Summary, or strict communication gates |
| 3 | Control + C3 + E1 × 15 | E1 produced clean Summary endings | independent audit found full bodies remained copy-edit level 15/15 and original comparison was `4/11/0`, not the earlier claimed `5/10/0` |

Phase 0's historical five-cell results are retained as context: Luna low with
the revised retention prompt had `60/60` mean/min retention and was faster than
the other safe cells; GPT-5.4 medium had a critical exact-title failure. That
was evidence about retention under a different prompt, not evidence that Luna
communicated best.

Phase 2 showed why direct promotion of the earlier GPT-5.4 full-body candidate
was unsafe: C3 retained `248/248` body checklist items but invented unsupported
intent in one Summary, and its runner emitted a literal terminal `\\n` artifact.
Phase 3 fixed those specific defects but did not cross the material-rewrite
bar. The architecture, rather than a further synonym-level rewrite prompt, had
to change.

## Phase 5 — summary-only selection

Phase 5 used the five hardest fixtures: orchestrator installation, plugin
registry correction, reciprocal SSHFS deadlock, Screen Verify focus issue, and
the Fn+Esc mute trace. The original was retained in place for every comparison;
only the companion brief changed.

### Exploratory GPT-5.4 versus Luna

The first blind comparison used exploratory Prompt G with `gpt-5.4` medium
against Luna low. GPT-5.4 was preferred for communication and retention in all
`5/5` fixtures. Its winning briefs were 80, 107, 114, 105, and 71 words. The
three over-100 results motivated the final 120-word Prompt H ceiling: it allows
safety-relevant detail that the shorter alternatives lost while still requiring
a compact companion. These G outputs are model-selection context, not the final
Prompt H production evidence.

### Final GPT-5.4 versus GPT-5.5 blind

An additional blind Prompt H comparison preferred GPT-5.4 in `4/5` fixtures
and GPT-5.5 in `1/5`. This is model-preference evidence only. The exact
GPT-5.4 Prompt H rerun below, rather than a mixture of exploratory or
per-case outputs, is the production-fidelity result.

### Exact GPT-5.4 Prompt H rerun

The exact production prompt was rerun with GPT-5.4 medium on all five hard
fixtures. Cases 01, 08, 09, and 12 were deployable under the strict
zero-distortion review. Case 05 was not: its third bullet transferred the
generic “actively use” condition to `deep-research`, where the source instead
required the more specific DOCX-style multi-pass condition. Prompt H is
therefore `4/5` under this strict audit, not perfect fidelity. The unchanged
original above the brief remains authoritative.

This case-05 result is an important provenance correction. An earlier final
case-05 review found a different GPT-5.4 H sample deployable because it kept
the distinct condition. A stricter earlier audit also recorded selective
omission of the admission, user credit, registry paradox, and its hedged
inference. Neither result makes every Prompt H sample perfect; they show why
the production choice is the best observed companion-brief tradeoff rather
than a claim of complete summary retention.

### Rejected Prompt I

Prompt I strengthened condition binding and was also tested with GPT-5.4
medium on all five fixtures. It was deployable in only `3/5`, so it was not
promoted. In case 08 it changed “no mount **access** was performed” to “no
**mount** was performed,” altering the denied event and status. In case 12 it
dropped the required `done +` prefix from the `done + unchanged` reporting
alternative. Stronger condition wording did not compensate for those exact
status losses.

## Evaluation limits

- Five final fixtures are a difficult technical slice, not a representative
  sample of every user, language, or conversation style.
- Each model/fixture pair was sampled once; output variance and latency tails
  were not measured.
- The blind final review compared opaque candidates. Its model mapping is made
  only after the evaluation; the preference result is still a small sample.
- A concise brief cannot carry every supporting detail. The original response
  is therefore intentionally retained above it and remains authoritative.

## Tracked implementation

- [`dotfiles/codex/hooks/response-simplifier.sh`](../dotfiles/codex/hooks/response-simplifier.sh)
  sets the 1,500-character gate, `gpt-5.4`, `medium` effort, 120-second
  timeout, isolated child execution, and fail-open behavior.
- [`dotfiles/codex/response-simplifier.md`](../dotfiles/codex/response-simplifier.md)
  is Prompt H. It produces only a compact `**First Mate**` brief and never a
  replacement body rewrite.

The hook measures the original response before generation. A 1,494-character
message remains bypassed by the 1,500-character gate; measuring the brief
instead would change that behavior.
