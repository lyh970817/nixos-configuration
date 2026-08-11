# Stop-hook companion brief evaluation

## Current decision

Use `gpt-5.4` at `medium` reasoning effort with the grouped route-aware prompt
whose SHA-256 is
`423b5b3526c6e077072339986438f60a2442f1975774b4934bd04b750fda0c5c`.
The hook leaves the finished assistant response unchanged and adds only a short
companion brief below it. The brief gives each selected route its own heading,
then places local `Category:` bullets beneath it in the declared route and
category order. Within Result, it requires exactly one Outcome and partitions
implementation details, checks, and limits into Changes, Verification, and
Boundary without repeating facts. Multiple independent items may use one
category label with numbered entries; the prompt has no numeric word cap.

The prompt routes each response as Result, Decision, Research, Brainstorming,
or Progress. That routing changes what the brief prioritizes: an outcome and
boundary; an answer or choice; a finding, evidence limit, and implication;
unselected possibilities, tradeoffs, and open questions; or completed, current,
pending, and required action. It does not scrape the last user message or the
conversation transcript. The completed assistant response is the sole source,
and the original remains visible and authoritative.

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

This does not make the brief complete. It may omit lower-priority background
while the original remains directly above it, but it must cover each distinct
reader-facing choice or action or direct the reader to the complete exact set in
the original. It must not distort conditions, ownership, scope, verification,
or safety boundaries.

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
human-auditable checklists. The later retained setups standardized on Codex CLI
0.147.0, an ephemeral read-only child, disabled hooks/user configuration, a
common `<message>` envelope, and an outer 120-second timeout. Phase 0 does not
support that universal runner claim: A's retained `run.sh` used parallelism 5
and no outer 120-second timeout, while B's runner is absent and its Luna/low
identity comes from the supplied experimental definition rather than
self-contained output metadata; B's manifest suggests sequential scheduling.
Blind judges saw opaque candidates, not model or prompt identity.

| Phase | Matrix | Result | Why it was not the final design |
| --- | --- | --- | --- |
| 0 | 5 models/prompts × 15 | Luna low/revised was selected for safety | later audit found it expanded all 15 outputs and produced no separate useful summary; the revised prompt had not encoded that product requirement |
| 1 | Control + 6 cells × 15 | Luna low/stronger-brief prompt passed retention | only `+1.13` mean body gain, `+1` median, no `+4` case; 8/15 material rewrites |
| 2 | Control + 6 cells × 15 | historical `**Summary**` contract recovered | every candidate failed retention, safety, Summary, or strict communication gates |
| 3 | Control + C3 + E1 × 15 | E1 produced clean Summary endings | the blind identity and detailed E1 rows reproduce `4/11/0` and copy-edit-level bodies 15/15; the stored `5/10/0` aggregate is arithmetically inconsistent |

Phase 0's historical five-cell results are retained as context: Luna low with
the revised retention prompt had `60/60` mean/min retention and was faster than
the other safe cells; GPT-5.4 medium had a critical exact-title failure. That
was evidence about retention under a different prompt, not evidence that Luna
communicated best.

Phase 2 showed why direct promotion of the earlier GPT-5.4 full-body candidate
was unsafe: C3 retained `248/248` body checklist items but invented unsupported
intent in one Summary, and its runner emitted a literal terminal `\\n` artifact.
Phase 3 fixed those specific defects but did not cross the material-rewrite
bar. Joining its blind identity map to the detailed communication judgments
gives E1 four wins, 11 ties, and no losses against the original; all 15 E1 rows
are `copy_edit` with `material_editorial_change=false`. The stored aggregate's
`5/10/0` field disagrees with those rows, and its validation did not check that
arithmetic. The row-derived `4/11/0` is therefore the reproducible result. The
architecture, rather than a further synonym-level rewrite prompt, had to change.

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

### Mixed GPT-5.4-side versus GPT-5.5 blind

The surviving final-blind2 manifest shows that the GPT-5.4 side used Prompt G
on cases 01, 08, 09, and 12 and Prompt H on case 05, while the GPT-5.5 side used
Prompt H on all five. After unblinding, the GPT-5.4-side configuration was
preferred in `3/5` fixtures and GPT-5.5 in `2/5`. Because the GPT-5.4 side mixed
prompts, this is configuration evidence, not a controlled Prompt H model
comparison. The exact GPT-5.4 Prompt H rerun below remains the separate
production-fidelity result.

### Exact GPT-5.4 Prompt H rerun

The exact production prompt was rerun with GPT-5.4 medium on all five hard
fixtures. Cases 01, 08, 09, and 12 were deployable under the strict
zero-distortion review. Case 05 was not: its third bullet transferred the
generic “actively use” condition to `deep-research`, where the source instead
required the more specific DOCX-style multi-pass condition. Prompt H is
therefore `4/5` under this strict audit, not perfect fidelity. The unchanged
original above the brief remains authoritative.

This case-05 result is an important provenance correction. The deployable
case-05 sample in the earlier mixed comparison was GPT-5.5 with Prompt H, not
GPT-5.4. A retained GPT-5.4/H audit also recorded selective omission of the
admission, user credit, registry paradox, and its hedged inference. The retained
GPT-5.4/H samples therefore do not establish perfect case-05 reliability; they
show why the production choice is a tradeoff rather than a claim of complete
summary retention.

### Rejected Prompt I

Prompt I strengthened condition binding and was also tested with GPT-5.4
medium on all five fixtures. It was deployable in only `3/5`, so it was not
promoted. In case 08 it changed “no mount **access** was performed” to “no
**mount** was performed,” altering the denied event and status. In case 12 it
dropped the required `done +` prefix from the `done + unchanged` reporting
alternative. Stronger condition wording did not compensate for those exact
status losses.

## Route-aware summary-only evaluation

The later evaluation simplified the question to prompt design with one selected
generator model: GPT-5.4. It did not run another model tournament. The baseline
corpus had ten route-balanced cases, two each for Result, Decision, Research,
Brainstorming, and Progress. Eight were audited real top-level responses. Two
Brainstorming cases were explicitly synthetic because the available history had
no suitable genuine top-level examples of that route.

The medium-effort v1 and v2 prompts established that GPT-5.4 could select the
correct route but still lose conditions or broaden scope under compression. A
v3 iteration changed the prompt and effort together, so it was not an effort
ablation. That high-effort configuration took 33.211–84.003 seconds per case
and passed only `6/10` safety reviews. The configuration did not justify its
latency or resolve fidelity consistently, so production retained medium effort.

### ASD-STE100-instruction replacement

V4 compared the detailed route-aware prompt
`aea40cb9ad4401ab27afccaef10dffbfca381379a50e5a2168ff1714d67344b8`
with a minimal “Speak in ASD-STE100 Simplified Technical English” prompt
`46a45af3f9f794b378b1cb850ec650be18e004fc4aee987994fb146d2a7df557`.
Both cells used GPT-5.4 at medium effort on the same six cases. Both selected
the intended route in `6/6`. The detailed prompt won all `6/6` blind
communication comparisons and passed safety in `3/6`; the ASD-STE100 prompt
passed safety in only `1/6`.

The minimal instruction addressed surface wording but did not supply the
missing routing and fidelity semantics: which result boundary, choice, evidence
limit, open question, or pending action must survive compression. It was
therefore not deployed by itself.

The packaged runner aborted when it encountered a pre-existing detailed-cell
run before reaching the ASD-STE100 cell. The same packaged invocation and
schema were replayed cell-only into the distinct ASD-STE100 namespace, and
output integrity was validated before blind review.

### Focused v5 correction

V5 tested the then-deployed flat-bullet prompt on the three remaining targeted
regressions. Its SHA-256 is
`f4e6999c696a55829d708d5bc4266605efe86930a7644e6c1e3818f4716f5f29`.
It passed communication in `3/3` and safety in `2/3`.

The residual failure was a dense orchestrator Progress report. Its brief lost
the plugin/no-plugin decision and the safer `--approve-for-me` launcher, and it
broadened the scope of the project `AGENTS.md`. The candidate therefore failed
the focused zero-failure production-acceptance criterion. Deployment
deliberately accepts this residual because the unchanged original remains
visible and authoritative; this is the best observed tradeoff, not a claim of
perfect retention.

### Grouped route-label comparison

The grouped candidate was compared with that flat-bullet prompt on a distinct
five-case set: cases 01 (Codex orchestrator installation), 13 (datetime/OpenSSL
rebuild outcome), 14 (Codex skill-cleanup recommendation), 15 (documentation
status audit), and a synthetic session-handoff exploration. This is not the
earlier Phase 5 five-hard-fixture set. Both configurations used `gpt-5.4` at
medium effort with one sample for each configuration/fixture pair.

A strict independent audit of the exact candidate rejected promotion: it found
critical table/scope loss in case 01, critical table/classification loss in case
15, and no Brainstorming route in the synthetic case, for expected-route
inclusion of `4/5`. The synthetic candidate retained content, but placed its
unselected tradeoffs and open questions under Progress rather than Brainstorming.
That audit prevents treating this deployment as a zero-distortion certification.

The later blind pairwise result uses a narrower comparative gate. It preferred
the candidate for communication grouping in `5/5`; critical safety was
`PASS/PASS` for candidate/control in every fixture, where the gate covered
invented reader actions, broadened verification, false selection or execution,
and lost safety-relevant boundaries. Candidate retention passed `5/5`, compared
with the control's `3/5`. The candidate was selected as a deliberate
communication tradeoff because route headings and route-local `Category:`
bullets improve orientation while the original remains visible and authoritative,
not because the candidate is certified free of distortion or reliable generally.

### Focused Result-partition correction

A user-reported live regression produced three nested Outcome entries instead
of partitioning the result. A focused six-case comparison then evaluated only
`gpt-5.4` at `medium` effort with the current, v1, v2, and v3 prompts; it was a
prompt comparison, not a model or effort comparison. V3 was preferred in all
`6/6` blind communication comparisons against current and produced no sampled
invention, contradiction, false completion, unsafe reader action, or false
option selection.

On the observed case, v3 restored exactly one Outcome, distinct Changes,
Verification, and Boundary entries, and the explicit implemented, committed,
synced, rebuilt, and verified lifecycle statuses. It did not clear a
zero-failure gate: the relationship between the interactive composer and its
verification was not explicit, the documentation case emitted Research before
Result and compressed row-level reasons and exact classification labels, and a
separate dense Result still omitted exact evidence details without pointing to
the complete original. The literal final adjudication was therefore `3/6`, not
a certification of complete retention.

The selected v3 prompt has SHA-256
`423b5b3526c6e077072339986438f60a2442f1975774b4934bd04b750fda0c5c`.
Its non-distorting sampled failures were accepted as a communication tradeoff
because the unchanged source remains visible and authoritative above every
brief; that condition remains part of the design's safety boundary.

## Evaluation limits

- The five historical final fixtures, ten route-balanced baseline cases, and
  focused regression cases are technical slices, not representative samples of
  every user, language, or conversation style.
- Each evaluation cell and fixture pair was sampled once; output variance and
  latency tails were not measured.
- Blind reviews compared opaque candidates. Their model or prompt mappings were
  disclosed only after evaluation; the results are still small samples.
- A concise brief cannot carry every supporting detail. The original response
  is therefore intentionally retained above it and remains authoritative.

## Tracked implementation

- [`dotfiles/codex/hooks/response-simplifier.sh`](../dotfiles/codex/hooks/response-simplifier.sh)
  sets the 1,500-character gate, `gpt-5.4`, `medium` effort, 120-second
  timeout, isolated child execution, and fail-open behavior.
- [`dotfiles/codex/response-simplifier.md`](../dotfiles/codex/response-simplifier.md)
  is the grouped route-aware production prompt. It produces only a headed,
  route-local-category companion brief and never a replacement body rewrite.

The hook measures the original response before generation. A 1,494-character
message remains bypassed by the 1,500-character gate; measuring the brief
instead would change that behavior.
