# Grammar/polish prompt experiment results (2026-08-23)

Question: is a more aggressive cleanup prompt than TIDY worthwhile — one that
also fixes grammar (`e-grammar`) or rewrites each sentence into
carefully-written prose (`f-polish`)? Both variants keep TIDY's
transcription-only guard verbatim (the d-none control showed the model answers
the speech without it).

Same setup as `RESULTS.md`: model `qwen3.5-omni-plus-realtime`, the same
deterministic 20-utterance selection (archive unchanged at 357 wavs), one warm
realtime session per condition. Scored with `score-polish.py`, whose rubric
tolerates rewording (polish intentionally rewords, so `score.py`'s
"wording removed / words invented" counts would falsely penalize it) and
instead judges meaning drift, entity/term fidelity, contract violations,
residual grammar errors, and over-polish, per utterance via `claude -p`
against the provider's raw ASR transcript.

| metric | c-tidy | e-grammar | f-polish |
|---|---|---|---|
| meaning drift | 4 | 7 | 7 |
| entities/terms changed | 6 | 6 | 7 |
| contract violations | 0 | 0 | 0 |
| grammar errors residual | 1 | 0 | 0 |
| over-polish | 0 | 1 | 2 |
| fillers retained | 0 | 0 | 0 |
| output/reference length ratio (median) | 1.00 | 1.00 | 1.00 |
| commit->final median ms | 616 | 603 | 568 |
| commit->final p90 ms | 838 | 946 | 717 |
| utterances judged | 20 | 20 | 20 |

Reading:

- **The outputs are nearly identical across all three conditions.** The model
  barely exercises the extra permissions: under `f-polish`, plainly awkward
  spoken phrasing ("I probably wouldn't be like coding for projects and so
  on … and also like browse, use my browser") survived verbatim. The polish
  instruction does not actually buy polish from this realtime model.
- **The only genuine grammar gain in 20 utterances**: `e-grammar`/`f-polish`
  fixed "if the existing infrastructure is not the optimal" to "is not
  optimal"; `c-tidy` kept the speaker's error. That is the entire upside.
- **`e-grammar` introduced real errors.** "How can it actually be false?"
  became "How can a shape be false?" (hallucinated referent), and "on the
  portable laptop" became "on a portable laptop" (article over-correction
  that loses which laptop is meant — this text is pasted into Claude
  sessions where that specificity matters).
- **`f-polish` shifted meaning-bearing modality**: "would it be fixed?"
  became "will it be fixed?" (hypothetical turned future).
- A shared error floor moves with hearing variance, not with the prompt:
  all three misheard "OpenAPI" as "opening", all three normalized ".codec";
  "this is fair" came out "this is fat" in the e/f sessions but not the
  c-tidy session, and conversely `c-tidy`/`f-polish` corrected "Nihongo" to
  "Mihomo" while `e-grammar` did not. Several flagged "changes" are the
  cleanup hearing the audio better than the raw-ASR reference ("create space
  on my desk" -> "free space on my disk").
- Latency is indistinguishable (~600 ms median everywhere; the p90 spread is
  single-utterance noise).

Decision: **don't ship either; `c-tidy` stays the default.** The measurable
gain is roughly one minor grammar fix per 20 utterances; the cost is new
hallucination-class errors (GRAMMAR) and modal/hedge shifts (POLISH) in text
that is mostly pasted as instructions into chat/code contexts, where a wrong
referent or article is worse than a preserved grammar slip — and POLISH does
not even deliver the careful prose it asks for. The variant prompts remain in
`prompts/` for `replay.py --conditions`.

Raw per-utterance outputs and judgements are not committed (they contain
dictation content); re-run `replay.py` + `score-polish.py` to regenerate.
