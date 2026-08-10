# Stop-hook rewrite model comparison

## Decision

Use `gpt-5.6-luna` at `low` reasoning effort with the revised response
simplifier prompt. This was cell B, blind variant R5. It retained all `227/227`
checklist items across the 15 fixtures, had no invention or hard cap, achieved
the best holistic result (`99.400` mean, `99` minimum), and was the fastest of
the three production-safe revised-prompt cells on observed mean, median, and
maximum latency.

The revised prompt has SHA-256
`04decca9b2d1f7bbace81e4df6bd078ef5bcd4092e060aba8245b817e2cdade6`.
It was adopted in commit `053080f1` (`Preserve stop hook response details`).

## Community research context

A `last30days` v3.18.4 run on 2026-08-10 gathered 139 items: 16 Reddit
threads, 26 X posts, 7 YouTube videos with transcripts, 16 TikToks, 5
Instagram reels, 32 Hacker News stories, 13 GitHub items, 23 Digg clusters,
and 1 Techmeme headline. Reddit coverage was partial after HTTP 429 responses.
The directly ranked clusters were poorly focused on communication style, so
the synthesis relied heavily on web supplements and a prior focused Opus 5
artifact.

That research supplied candidates, not proof of model quality:

- GPT-5.4 was most often described as warmer, more vivid, and more
  conversational, with a counter-warning that it can sound better while
  thinking worse.
- GPT-5.6 criticism centered mainly on Sol over-engineering, carrying
  superseded constraints, unnecessary elaboration, and exceeding user intent.
  Terra-specific tone evidence was thin and mixed.
- GPT-5.5 had little recent preference evidence. Luna had almost no
  family-specific communication evidence and remained the speed baseline.
- GPT-4o and GPT-5.1 still received praise for natural conversation, but they
  were absent from the locally selectable Codex model cache.
- Claude Opus 5 received praise for depth, but criticism emphasized verbosity,
  jargon, argumentativeness, and burying information.

This was self-selected community evidence across mixed tasks. It cannot
estimate how prevalent any opinion is, and its sentiment did not determine the
production choice.

## Controlled evaluation

The corpus contained 15 recent technical responses from this repository,
spanning 1,040 to 7,279 characters. It covered diagnoses, implementation and
rebuild outcomes, corrections, design recommendations, external research,
network and security-sensitive explanations, exact commands and tables,
uncertainty, pending work, and near-threshold responses. Each source had a
human-auditable checklist of material facts, decisions, instructions, exact
tokens, qualifications, and status claims.

Five cells each rewrote all 15 fixtures once, producing 75 runs:

| Cell | Model | Effort | Prompt | Blind variant |
| --- | --- | --- | --- | --- |
| A | `gpt-5.6-luna` | `low` | current | R3 |
| B | `gpt-5.6-luna` | `low` | revised | R5 |
| C | `gpt-5.6-terra` | `medium` | revised | R4 |
| D | `gpt-5.4` | `medium` | revised | R1 |
| E | `gpt-5.5` | `medium` | revised | R2 |

The cells used Codex CLI 0.147.0 with the same `<message>` envelope, ephemeral
read-only execution, hooks and user configuration disabled, and a 120-second
timeout. Cell A used the then-current prompt, SHA-256
`d1032e9718e4228349c06ae04310f570fbb8170f40f7f26cd0672003df320417`;
the other four used the revised prompt.

Before judging, the outputs were copied under randomized opaque IDs R1–R5.
Judges were given source responses, checklists, the common rubric, and the
opaque rewrites, but not the cell identities. They evaluated one fixture across
all five variants at a time. All 75 blind-output checksums passed, every cell
had 15 outputs, and each output matched its later-unblinded source cell
byte-for-byte.

## Rubric and decision rule

The 100-point rubric assigned 40 points to factual retention, 20 to instruction
and decision retention, 15 to clarity and naturalness, 15 to concision, and 10
to formatting. Checklist items received `2` for full retention, `1` for a
weakened non-critical detail, or `0` for omission, contradiction, distortion,
or attachment to the wrong subject.

Penalties and caps guarded against fluent but unsafe rewrites: each invention
lost 10 points; contradictions or reversed recommendations capped the score at
50; one omitted critical item capped it at 70 and two at 50; false completion
claims capped it at 40; and a rewrite requiring missing context capped it at
60.

A dedicated retention judge scored the first 60 points, including invention
penalties and caps. A separate communication judge scored the remaining 40.
Their split composite was reported alongside an independent holistic 100-point
audit instead of averaging the two overlapping views. A cell was production
eligible only if it had no invention, no critical-omission cap, and no fixture
below 90 in the holistic audit.

## Results

| Rank | Cell / blind ID | Configuration | Retention mean / min (`/60`) | Holistic mean / min (`/100`) | Latency mean / median / max |
| ---: | --- | --- | ---: | ---: | ---: |
| 1 | B / R5 | Luna low, revised | 60.000 / 60.00 | 99.400 / 99 | 32.225 / 27.408 / 54.434 s |
| 2 | C / R4 | Terra medium, revised | 59.879 / 58.18 | 99.147 / 97.2 | 32.310 / 28.593 / 56.279 s |
| 3 | E / R2 | GPT-5.5 medium, revised | 60.000 / 60.00 | 99.333 / 99 | 33.357 / 29.689 / 55.588 s |
| 4 | D / R1 | GPT-5.4 medium, revised | 59.704 / 55.56 | 97.067 / 70 | 34.066 / 27.734 / 55.068 s |
| 5 | A / R3 | Luna low, current | 49.670 / 8.00 | 73.500 / 39.8 | 30.007 / 29.333 / 51.281 s |

B, C, and E were production-safe. D changed an exact required issue title on
fixture 14 and received a critical cap, making its otherwise high mean
insufficient. A had seven capped fixtures and one invented pending-apply
question; it repeatedly removed exact commands, measurements, evidence,
matrices, and conditional rationale.

### Prompt effect

A and B held the model and effort constant, isolating the prompt change. The
revised prompt increased retention mean by `10.330/60`, split-composite mean by
`29.775/100`, split minimum by `70`, holistic mean by `25.900`, and holistic
minimum by `59.2`. It reduced capped fixtures from seven to zero and inventions
from one to zero. Mean latency rose by `2.218 s`, while median latency fell by
`1.925 s`. The prompt, rather than the model choice, was the decisive
intervention.

### Model effect and runner-ups

With the revised prompt held constant, the three safe cells were close. Terra
medium was the communication and split-composite winner, but omitted the exact
qualifier `single` from fixture 13's authorized rebuild claim. That lowered its
retention mean and holistic minimum, so C is the runner-up rather than the
selection.

GPT-5.5 medium is the close third and the alternate if perfect observed
checklist retention is treated as the sole criterion after safety. It matched
B's `60/60` retention but did not improve communication, was marginally lower
holistically, and was slower. The controlled result did not support preferring
GPT-5.4 on reputation: its single critical failure disqualified it.

## Timeout result

All `75/75` calls succeeded with no timeout or empty output. The largest
observed wall time was `56.279 s`, leaving `63.721 s` below the production
timeout. The 120-second limit was therefore not binding on this corpus.

This does not establish tail behavior: there was only one timing observation
per cell and fixture, so the evaluation did not measure run-to-run variance.
The `0.085 s` mean difference between B and C is too small to treat as a stable
general model-speed estimate.

## Limitations

- The 15 fixtures are technical responses from one repository. They stress
  exact retention well but do not represent every conversation style or
  language.
- Each cell ran each fixture once. There was no repeated or randomized trial
  design for output variability or latency tails.
- The judges applied a detailed common rubric, but clarity and materiality
  judgments still contain human judgment. The independent holistic audit
  reduces, rather than removes, that limitation.
- Cell B did not retain self-contained invocation metadata. Its model and
  effort identity came from the predefined experimental cell, while its prompt
  hash, output hashes, blind mapping, success status, and timings were
  independently verified.
- The findings compare only these five cells, this prompt pair, this model
  availability snapshot, and Codex CLI 0.147.0. They are not a general model
  ranking.

## Tracked implementation

The production behavior is defined by two tracked files:

- [`dotfiles/codex/hooks/response-simplifier.sh`](../dotfiles/codex/hooks/response-simplifier.sh)
  sets the 1,500-character gate, `gpt-5.6-luna`, `low` effort, the 120-second
  timeout, isolated child execution, and fail-open behavior.
- [`dotfiles/claude/response-simplifier.md`](../dotfiles/claude/response-simplifier.md)
  is the revised prompt source adopted in `053080f1`. It makes fidelity more
  important than brevity, requires exact technical content and status to be
  preserved, and permits only genuine filler and repetition to be removed.

The hook measures the original response before generation. In particular, the
1,494-character fixture near the threshold remains bypassed by the
1,500-character gate; measuring the generated rewrite would change that
behavior.
