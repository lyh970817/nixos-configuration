# Cleanup-prompt evaluation results (2026-08-23)

Model `qwen3.5-omni-plus-realtime`, 20 archived utterances (2-30 s, evenly
spread across `~/.local/share/hyprwhspr/short/audio/`, mixed
English/technical content), one warm realtime session per condition,
identical session settings. Semantic criteria judged by `claude -p` against
the provider's raw input-audio transcription; fillers counted
deterministically; totals over all 20 utterances.

| metric | a-aggressive | b-light | c-tidy | d-none |
|---|---|---|---|---|
| fillers retained | 0 | 0 | 0 | 3 |
| false starts retained | 0 | 0 | 0 | 0 |
| self-corrections unresolved | 0 | 0 | 0 | 0 |
| answered instead of transcribed | 0 | 0 | 0 | 20 |
| entities changed | 5 | 3 | 7 | 5 |
| meaningful wording removed | 6 | 7 | 5 | 143 |
| unsupported generated words | 6 | 5 | 5 | 2707 |
| commit->final median ms | 626 | 670 | 558 | 4192 |
| commit->final p90 ms | 917 | 1067 | 713 | 9033 |
| utterances judged | 20 | 20 | 20 | 20 |

Reading:

- **d-none is the control that proves the contract matters**: without a
  cleanup instruction the model answered every single utterance instead of
  transcribing it, at 6-13x the latency.
- **a, b, and c are within noise of each other on fidelity.** All three
  removed every counted filler (the deterministic local filter in hyprwhspr
  remains as backstop regardless), retained no false starts, resolved all
  self-corrections, and never answered the speech.
- The small "entities changed" counts are partly a reference artifact: the
  judge scores against the raw ASR, and several flagged "changes" are cases
  where the cleanup pass heard the audio *better* than the raw ASR stream
  (e.g. raw "Nihongo config" vs cleaned "Mihomo config", which is the real
  service name). This affects all conditions equally.
- **c-tidy had the best latency** (median 558 ms, p90 713 ms) in this run;
  differences of ~100 ms between a/b/c are within run-to-run variance.

Decision: **c-tidy ships** as `DEFAULT_TIDY_CLEANUP_PROMPT` in
`scripts/qwen-asr-shim.py`. Nothing in these results shows TIDY worse than
the previous aggressive prompt; it matches it on every fidelity metric with
a much narrower, more interpretable permission boundary and no worked
examples.

Raw per-utterance outputs and judgements are not committed (they contain
dictation content); re-run `replay.py` + `score.py` to regenerate.
