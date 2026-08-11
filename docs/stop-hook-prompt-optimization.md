# Stop-hook prompt optimization retrospective

## Outcome

The production design is a route-aware companion brief, not a replacement
rewrite. The [hook](../dotfiles/codex/hooks/response-simplifier.sh) leaves the
completed assistant response visible and unchanged, then uses `gpt-5.4` at
`medium` reasoning effort to add a short brief below it. The
[prompt](../dotfiles/codex/response-simplifier.md) treats that original as its
only source and as the authoritative report.

The brief silently routes the source as Result, Decision, Research,
Brainstorming, or Progress, then emits each selected route as a heading with
route-local `Category:` bullets beneath it. Result requires exactly one Outcome
and partitions details, checks, and limits into Changes, Verification, and
Boundary without repeating facts. The prompt can use numbered items beneath one
category label when independent facts require them and has no numeric word cap.
The hook still has a 1,500-character input gate, a 120-second timeout, isolated
read-only execution, disabled child hooks, and fail-open behavior. The current
prompt SHA-256 is
`423b5b3526c6e077072339986438f60a2442f1975774b4934bd04b750fda0c5c`.

What was optimized was therefore not the quality of the original assistant
answer. It was the reader's ability to orient quickly after a long answer while
retaining access to its evidence, exact commands, caveats, and reasoning. That
distinction eventually changed the objective, prompt, rubric, corpus, and
acceptable failure boundary. The detailed scores and model cells remain in the
[companion evaluation report](stop-hook-model-comparison.md); this document
records the design reasoning and lessons.

## How the design evolved

The lineage began in the Claude Stop hook as a full plain-English replacement.
It gained a trailing `**Summary**`, then three capped sections, topic-floor
coverage, a 1,500-character threshold, and a `<message>` source boundary. The
Codex hook initially reused that prompt with Luna at low effort. The
retention-first rewrite affected the shared prompt; the Claude and Codex prompt
tracks then split, and this retrospective follows the Codex track from that
point. Later Claude-only section changes are not evidence about the Codex
companion brief.

| Stage | Experiment | What it established |
| --- | --- | --- |
| Legacy full rewrite | Replace the whole response with plainer English, later forcing capped sections and a topic floor | A replacement must reproduce every valuable detail, so brevity and fidelity compete directly. Fixed shapes also make the output longer when the source does not need them. |
| Retention-first evaluation | Strengthen the full-rewrite prompt and compare models on 15 technical cases | Explicit retention policy was associated with fewer dangerous omissions, but the winner expanded all 15 sources and supplied no separate useful summary. The prompt had not encoded that product requirement, so safety under a retention-heavy rubric did not solve communication. |
| Better full bodies | Compare the original with prompts aimed at more material rewriting | The best full-body candidate gained only `+1.13` mean and `+1` median, had no `+4` case, and was materially better in only `8/15`; already-strong originals left little room before the scoring ceiling. |
| Full body plus Summary | Recover a historical Summary ending, then refine condition binding and runner behavior | A good Summary could coexist with a near-copy body, and a flawless body checklist could coexist with an invented Summary. More output created another surface for distortion without resolving duplication. |
| Summary-only pivot | Keep the original and compare Prompts G, H, and I on five hard cases | Once the original stayed visible, the new output could optimize selective orientation rather than complete replacement. Prompt H reached `4/5` in its exact fidelity audit; the more constrained Prompt I fell to `3/5`. |
| Route-aware v1 and v2 | Use two cases for each of five response purposes | Route selection was consistently `10/10`, but correct classification alone did not stop lost conditions, partial sets, and broadened scope. |
| Route-aware v3 | Change both prompt and reasoning effort | Routing again reached `10/10`, but safety was `6/10` and calls took 33.211–84.003 seconds. Because prompt and effort changed together, this was a configuration test, not an effort ablation. |
| V4 ASD-STE100-instruction replacement | Replace the detailed prompt with one sentence requesting ASD-STE100 Simplified Technical English on six cases | Both cells routed `6/6`, but the detailed prompt won communication `6/6` and safety `3/6` versus `1/6`. Wording guidance did not replace semantic selection policy. |
| Focused v5 | Target the remaining known regressions and retest three cases | Communication passed `3/3` and safety `2/3`. The retained original made the residual loss acceptable as a known tradeoff, not as perfect fidelity. |
| Grouped route labels | Compare a route-heading and route-local-category candidate with the flat-bullet prompt on cases 01, 13, 14, 15, and a synthetic handoff exploration, distinct from the earlier five-hard-fixture set | The later pairwise gate preferred the grouped candidate `5/5`, with critical safety `PASS/PASS` in all five and retention `5/5` versus `3/5` for the control; a stricter independent audit rejected the exact candidate for table/scope and route defects. |
| Focused Result partition | Correct a user-reported three-Outcome regression and compare current, v1, v2, and v3 on six cases with GPT-5.4 medium only | V3 won `6/6` blind communication comparisons and fixed the observed Outcome/Changes/Verification/Boundary partition without inventions, contradictions, or false completions, but literal adjudication remained `3/6` because explicit composer-verification scope, exact dense evidence, and documentation order/classification detail were not all retained. |

The historical full-body packages and the later route-aware series used
different numbering schemes: the former jumps from Phase 3 to Phase 5, while
the latter has prompt versions v1 through v5. “V4” and “v5” below refer to the
route-aware series, not missing historical phases.

The initial retention result deserves special care because it looked much more
decisive than it was. Under the same stated Luna/low generator configuration,
the revised-prompt cell was associated with mean retention of `60.000` rather
than `49.670`, communication of `38.400` rather than `19.533`, a split composite
of `98.400` rather than `68.625`, and a holistic score of `99.400` rather than
`73.500`; capped cases fell from seven to zero. The fixtures, rubric, and
supplied model/effort identity matched, but the comparison is not fully
controlled: B lacks a retained runner and self-contained model metadata, while
A's retained `run.sh` used parallelism 5 and no outer 120-second timeout. The
B manifest suggests sequential scheduling, so scheduling differs as well. The
large association supports prioritizing prompt design over model reputation,
but it is not a clean causal estimate. It also did not meet the communication
objective: every selected output expanded its source, and none supplied a
separate useful summary. The revised prompt did not require one and discouraged
a merely repetitive summary, so the missing product requirement was a prompt
design error rather than a model instruction failure.

The later full-body work exposed the same mismatch from another direction. The
original response was already a strong communication baseline, but early
absolute scoring did not include it as a candidate. When it was included, most
improvements were copy edits near the top of the scale. Phase 2's C3 body kept
`248/248` checklist items but invented intent in its Summary, while its runner
also emitted a literal terminal `\\n`. Phase 3 removed those particular defects
but still produced copy-edit-level bodies in all 15 cases. Joining the blind
identity map to the detailed E1 judgments reproduces four wins, 11 ties, and no
losses against the original. The stored `5/10/0` aggregate is arithmetically
inconsistent with those 15 rows, and its validation did not check the aggregate
arithmetic. The row-derived `4/11/0` is the reproducible result, while the
architectural conclusion is unchanged.

## Why the architecture changed

A full rewrite implicitly promises that the replacement is at least as useful
and safe as the source. For technical work, that means retaining exact commands,
conditions, exceptions, ownership, verification boundaries, open choices, and
status. A prompt strict enough to protect all of those features tends to copy or
expand an already good answer. A prompt aggressive enough to shorten the answer
tends to drop or reattach them.

The display location made that tradeoff unnecessary. The stop hook's
`systemMessage` appears below the completed answer; it does not replace it.
Repeating the whole report therefore adds reading cost without adding access to
information. Keeping the original visible changes the brief's contract:

- The original supplies completeness and exact evidence.
- The brief supplies fast orientation and highlights what matters for the
  response's purpose.
- Lower-priority detail can stay only in the original, but scope, conditions,
  required actions, and choices must not be distorted.
- When a complete set or procedure cannot fit safely, the brief points to the
  complete exact set in the original instead of presenting a selective subset.

This was the decisive optimization. It removed the false requirement that one
generated text be both a materially shorter replacement and a complete carrier
of the source. The remaining problem became selective compression: identify the
kind of report, preserve the relationships that determine its meaning, and make
omission safe by leaving the source immediately available.

## Route semantics and recurring failures

Routes are not decorative labels. Each route defines which relationships have
priority during compression.

| Route | Preserve first | Recurring failure modes |
| --- | --- | --- |
| Result | Outcome and its boundary | Reporting success without the untested component, turning partial verification into end-to-end verification, or losing a material no-change or unverified boundary. |
| Decision | Answer, recommendation, or choice | Transferring one option's condition to another, omitting an open choice or required reader answer, or presenting part of a decision set as the whole set. |
| Research | Finding, evidence limit, and implication | Dropping the evidence limit, converting a hedge or inference into a fact, broadening the population or causal claim, or keeping data without its practical implication. |
| Brainstorming | Unselected possibilities, tradeoffs, and open questions | Making exploratory options sound selected, flattening meaningful tradeoffs, or closing questions that remain open. The baseline evidence is weaker here because its two cases were synthetic. |
| Progress | Completed, current, pending, and required action | Turning pending work into completion, losing actor or environment scope, omitting a safer invocation, or giving only part of a multi-step procedure. Dense reports can contain several independent decisions as well as status. |

Across routes, the hard unit was a relationship rather than a token. The words
could all look plausible while a condition moved to the wrong recommendation,
an actor changed, a project rule became universal, or separately verified
components became an end-to-end claim. Exact-token checking catches a missing
flag or prefix, but it cannot by itself catch those attachment errors.

This is why the prompt now names actor, component, environment, category,
applicability, condition, and verification scope. It also treats a set as an
integrity boundary: cover every distinct choice accurately or refer the reader
to the original; never summarize an arbitrary subset as if it were complete.
Route headings expose the selected purpose, and route-local `Category:` bullets
make each claim's role explicit without repeating a separate nautical/roleplay
negative.

## Model choice and what the comparisons mean

`gpt-5.4` at medium effort is the current generator because it produced the best
observed companion-brief tradeoff under the deployed architecture. Community
sentiment helped nominate models and failure hypotheses, especially verbosity,
stale constraints, and buried conclusions. It was self-selected evidence from
mixed tasks, so it did not measure model quality and did not select production.

Prompt design had the larger observed association. The two same-stated
Luna/low cells had a large retention and communication difference, although the
runner and provenance limitations above prevent a clean causal claim. Later,
changing from a full replacement to a companion brief changed the task itself
and made a short output useful without requiring it to stand alone. These are
stronger design reasons than online preferences about tone, not a controlled
effect-size comparison.

Several tempting model claims are not supported:

- Prompt G's GPT-5.4-medium side beat Luna-low `5/5`, but effort differed, so
  this is configuration evidence rather than a pure model comparison. The
  winning briefs were 80, 107, 114, 105, and 71 words; longer candidates won,
  and only two were at or below 100 words.
- The surviving final-blind2 manifest is not a controlled Prompt H comparison.
  The GPT-5.4 side used Prompt G on cases 01, 08, 09, and 12 and Prompt H on
  case 05, while GPT-5.5 used Prompt H on all five. Unblinding gave the mixed
  GPT-5.4-side configuration `3/5` and GPT-5.5 `2/5`.
- The exact GPT-5.4-medium Prompt H audit is separate and remains `4/5`.
- Route v3 changed the prompt and effort jointly. Its latency and `6/10` safety
  result do not isolate a causal effect of high effort.

Model, effort, prompt, corpus, rubric, and sample are all part of a cell. A
result should be labeled as a model effect only when the other relevant parts
are held fixed.

## ASD-STE100-instruction experiment

V4 was a controlled whole-prompt replacement. It compared the detailed
route-aware prompt with the single instruction “Speak in ASD-STE100 Simplified
Technical English” on the same six cases, using GPT-5.4 at medium effort in both
cells. Both outputs matched the intended route in `6/6`, but the detailed prompt
won every blind communication comparison. It passed safety in `3/6`; the
minimal ASD-STE100 cell passed `1/6`.

The useful interpretation is narrow. The sentence addressed surface wording
but did not say which boundary, condition, complete choice set, evidence limit,
open question, or pending action must survive. Easy route recognition was not
enough to preserve those semantics.

This did not test adding STE wording to the detailed route-aware policy. It did
not compare individual STE rules, and it did not audit either output for formal
ASD-STE100 compliance. The result rejects the minimal sentence as a replacement
for semantic policy; it does not reject a later additive wording experiment.

## How the evaluation method improved

The evaluation changed along with the product. Several early choices were
reasonable for a replacement rewrite but misleading for an orientation brief.

### Put the original in the comparison

The original was not initially a candidate baseline. Absolute scores could show
that an output was safe and readable, but not whether generation improved an
already strong source. Original-versus-candidate comparison later revealed the
near-ceiling full-body gains and made duplication visible.

### Separate retention from communication

A retention-heavy rubric rewarded safe copy edits. Human-auditable checklists,
exact-token audits, and hard caps for invention or critical omission were still
valuable, but they answered “did it preserve the source?” more directly than
“did it help the reader?” Later reviews separated safety/fidelity from blind
communication preference. A candidate can win one and fail the other; neither
score should erase that distinction.

### Prefer pairwise and case-specific judgment near the ceiling

Absolute, case-flat scoring compressed strong candidates into a narrow band and
gave every case the same influence regardless of its semantic density. Pairwise
comparison against the original or another candidate exposed small but useful
differences. Focused regression cases then tested known failure mechanisms
instead of diluting them in an easy average.

Raw pass rates from different phases are not a longitudinal leaderboard. The
prompts, corpora, rubrics, and acceptance gates changed. A `6/10` under one
safety review cannot be directly ranked against `4/5` or `2/3` under another
without describing those differences.

### Replace false precision with flexible brevity

Hard section, bullet, and word caps encouraged selective omission and awkward
compression. Prompt G showed that longer candidates could communicate better;
three of its five winners exceeded 100 words. Prompt H temporarily used a
120-word ceiling, but later route-aware work removed numeric word limits. The
current default still creates pressure toward brevity while allowing another
bullet when distinct answers or actions would otherwise disappear.

### Audit relationships as well as exact tokens

Checklists and exact-token audits caught lost flags, prefixes, counts, paths,
and status words. Provenance review caught source attachment and unsupported
claims. Together they exposed failures that fluency scoring missed: changing
“no mount access” to “no mount,” dropping the `done +` prefix, transferring a
DOCX-specific condition to `deep-research`, or broadening an `AGENTS.md` rule.

### Blind first, then unblind from durable manifests

Opaque candidates reduced preference bias, while hashes and byte-for-byte
checks protected the mapping. Unblinding must come from the recorded manifest,
not from per-case cohort inference. The mixed Prompt G/H GPT-5.4 side was once
summarized as a uniform Prompt H model comparison; inspecting the manifest
showed that the label was wrong even though the blind preferences themselves
remained usable as configuration evidence.

### Treat runner behavior as part of provenance

A literal `\\n`, a pre-existing output that aborted a packaged run, or a
replayed cell can change what was actually judged. Runner defects do not
automatically invalidate a result, but the recovery must preserve invocation,
namespace, schema, and output integrity and must be documented. Prompt hashes,
model and effort declarations, case manifests, output checksums, and blind
mappings matter as much as the prose summary.

### Do not overread one-shot timing

Each cell/case pair was generally sampled once. Output variance, latency tails,
and inter-rater reliability were not measured. Concurrent runs also make wall
time a noisy model property. Observed latency can reject an obviously poor
configuration for this hook, but small mean differences or a single slow case
are not stable speed rankings.

## Controlled and confounded evidence

| Evidence | Variables held fixed | Confound or limit | Supported conclusion |
| --- | --- | --- | --- |
| Initial Luna/low prompt comparison | Fixtures, rubric, and supplied model/effort identity | B lacks a retained runner and self-contained model metadata, and its manifest suggests sequential scheduling; A's runner used parallelism 5 without an outer 120-second timeout; one sample per case | The revised-prompt cell had a large numeric advantage, but the comparison does not isolate a causal prompt effect. |
| Prompt H versus Prompt I | GPT-5.4 medium and the five hard fixtures | One sample per prompt/case; exact failure mix matters | More condition wording did not monotonically improve safety: H audited `4/5`, I `3/5`. |
| V4 detailed versus minimal instruction | GPT-5.4 medium, six cases, runner, blind communication and safety reviews | It replaced the whole prompt and did not test formal STE compliance | Detailed semantic policy beat the minimal ASD-STE100 wording instruction on this sample. |
| Prompt G GPT-5.4 versus Luna | Prompt and five cases | Model and effort both differed | GPT-5.4 medium was the better observed configuration `5/5`, not proven to be the better model in isolation. |
| Final-blind2 GPT-5.4 side versus GPT-5.5 | Five cases and blind judging | Model differed and the GPT-5.4 side mixed Prompt G and H | The mixed GPT-5.4-side configuration won `3/5`; this is not controlled Prompt H model evidence. |
| Route v3 versus v1/v2 | Broad route-balanced design | Prompt and effort changed jointly; review details evolved | The v3 configuration did not justify deployment; it says nothing causal about effort alone. |
| Cross-phase pass rates | General technical domain | Corpus, prompt, rubric, and gate changed | Use them to describe each phase, not rank phases numerically. |
| Phase 3 detailed rows versus aggregate | Blind identity and 15 per-case E1 judgments | The stored `5/10/0` aggregate contradicts the row-derived `4/11/0`, and validation did not check its arithmetic | Use the reproducible `4/11/0`; recompute aggregates from detailed rows during validation. |

## Durable design principles

1. Preserve the original when the generated layer is an aid, not the primary
   answer; this lowers the cost of selective omission and keeps evidence
   inspectable.
2. Optimize the product architecture before polishing wording. Replacement and
   companion output are different tasks with different safety contracts.
3. Make compression route-aware. Result, Decision, Research, Brainstorming, and
   Progress prioritize different information.
4. Preserve semantic relationships, not only tokens. Conditions, ownership,
   scope, negation, uncertainty, and verification attachment determine meaning.
5. Treat a complete choice, action, procedure, or check set as indivisible;
   include it all or point to the complete exact set in the original.
6. Use flexible brevity. Defaults create useful pressure; rigid word caps create
   false concision when the case contains several distinct obligations.
7. Keep wording policy and semantic policy distinct. STE-style instructions
   constrain surface wording but cannot decide what must survive compression.
8. Test prompt architecture before trusting model reputation or community tone
   preferences. The largest same-stated-model association here accompanied a
   prompt change, although its runner provenance prevents a causal estimate.
9. Judge readability and safety separately. A fluent brief can distort the
   source, while a complete brief can add no communication value.
10. Blind preference review, then unblind with manifests, hashes, exact
    invocations, and provenance checks rather than inference.
11. Isolate one variable when making causal claims. Otherwise label the result
    as a configuration comparison.
12. Repeat hard cases. One-shot success is a sample, and known regressions are
    more informative than an average dominated by easy cases.

## Current limitation and acceptance rationale

Focused v5 passed communication in `3/3` and safety in `2/3`; its dense
orchestrator Progress brief omitted the plugin/no-plugin decision and safer
`--approve-for-me` launcher, and broadened which projects the reported
`AGENTS.md` rule applied to. That result describes the preceding flat-bullet
prompt, not the current grouped prompt.

The grouped candidate was then compared with that predecessor on a distinct
five-case set: cases 01 (Codex orchestrator installation), 13 (datetime/OpenSSL
rebuild outcome), 14 (Codex skill-cleanup recommendation), 15 (documentation
status audit), and a synthetic session-handoff exploration. This set is distinct
from the earlier five-hard-fixture set. Both configurations used `gpt-5.4` at
medium effort with one sample per configuration/fixture.

The exact candidate also received a stricter independent audit, which rejected
promotion for critical table/scope loss in case 01, critical table/classification
loss in case 15, and a missing Brainstorming route in the synthetic case
(expected-route inclusion `4/5`). The synthetic output retained content but
formally put unselected tradeoffs and open questions under Progress rather than
Brainstorming. This strict audit rules out a zero-distortion interpretation.

The later pairwise result uses a narrower comparative gate: it preferred the
candidate `5/5`; both candidate and predecessor passed that gate's critical
safety review in every fixture, while retention passed `5/5` for the candidate
and `3/5` for the predecessor. The grouped prompt was selected as a deliberate
communication tradeoff because headings and local categories improve orientation
without hiding the original, which remains directly above the brief and
authoritative. If the UI ever hides or replaces it, this acceptance rationale no
longer applies and the safety gate must become stricter.

## Remaining risks and next experiments

- Expand the corpus with genuine Brainstorming responses, mixed-route reports,
  nontechnical writing, multilingual answers, adversarial source text, and more
  cases near the 1,500-character threshold.
- Repeat generation on the hardest cases to measure variance and detect model
  drift rather than treating one sample as stable behavior.
- Compare effort levels with prompt, model, cases, runner, and rubric fixed;
  compare models under the same fixed conditions as a separate experiment.
- Test an additive STE-style wording condition on top of the detailed
  route-aware prompt,
  with a concrete rule subset and a separate formal-compliance audit if formal
  ASD-STE100 conformance is actually a goal.
- Measure latency distributions and tail behavior without concurrent-run
  confounds, and measure agreement between independent safety and communication
  judges.
- Audit the one-sentence bullet rule after removing the word cap. It can produce
  long compound sentences that are technically one sentence but harder to
  understand.
- Keep targeted cases for partial procedures, condition transfer, set
  completeness, actor/environment scope, and separately verified components.

## Evidence and reproducibility boundary

The durable sources are the linked production prompt and hook, their hashes,
this repository's history, and the [model-comparison report](stop-hook-model-comparison.md).
Experiment packages and runner outputs kept outside the repository are
transient and must not be the only support for a durable claim.

Only endpoint production prompts survive in tracked history. The experiment
corpora, checklists, runners, blind manifests, generated outputs, reviews, and
route v1–v4 prompt bodies are not tracked here. Their summarized results remain
useful design evidence, but repository-only reproduction stops at the recorded
hashes, history, and report.

One evidence bundle is retained off to the side of that boundary. It covers the
Stop-hook response rewriter on the Claude prompt track, not the Codex track this
document describes, and it lives at `~/.local/share/stop-hook-rewriter-corpus`
on the portable laptop. It is kept outside the repository deliberately, because
it quotes real working sessions verbatim, which makes it untracked by
construction rather than by a `.gitignore` entry that a later forced add could
defeat; it is machine-local and is not synchronised anywhere. Its corpus is a
rebuilt one, regenerated on 2026-08-10 from the local session transcripts after
the original was lost, so its case ids do not map to the historical ones and its
numbers must not be compared against figures recorded before that date.

Some surviving archives contradict themselves or later prose summaries. In
Phase 3 the detailed rows reproduce `4/11/0`, while the stored aggregate says
`5/10/0` and its validation misses the arithmetic defect. The mixed-prompt final
blind comparison shows a separate labeling failure. A result is only as
reproducible as its detailed judgments, manifest, invocation metadata, hashes,
validation arithmetic, and retained artifacts. Future experiments should
either retain a sanitized evidence bundle in the repository or state clearly
where reproduction stops.
