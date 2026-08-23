# Qwen dictation cleanup-prompt evaluation

Compares cleanup-prompt conditions on the same archived short-dictation audio
(`~/.local/share/hyprwhspr/short/audio/`), replayed through the DashScope
realtime API with the shim's session settings (flat `session.update`, text
modality, manual commit). This documents why the shim's default prompt
(`scripts/qwen-asr-shim.py`, `DEFAULT_TIDY_CLEANUP_PROMPT`) is the adapted
DoNotType TIDY contract.

Conditions (`prompts/*.txt`):

- `a-aggressive` — the previous shipped prompt: broader repair permissions
  (fix grammar, fix recognition errors, convert spoken syntax) plus worked
  examples.
- `b-light` — adapted DoNotType LIGHT fidelity clause in the same contract
  frame: no sentence casing, only pause-implied punctuation.
- `c-tidy` — adapted DoNotType TIDY contract; this is what ships.
- `d-none` — no cleanup instruction at all (provider default behavior).
- `e-grammar` — TIDY plus grammar fixes (agreement, tense, articles, dropped
  function words), keeping the speaker's word choice and sentence structure.
- `f-polish` — TIDY plus rewriting each sentence into carefully-written
  prose at roughly the original length.

Run (read-only use of the deployed dictation credentials; each run bills
DashScope for the replayed audio):

```sh
PY=$(systemctl --user cat qwen-asr-shim.service \
  | sed -n 's/^ExecStart=//p' | cut -d' ' -f1)
$PY replay.py --limit 20 --out results.json
python3 score.py results.json --out scores.json
```

`replay.py` records per utterance and condition the cleaned output, the
provider's raw input-audio transcription, and commit->final latency.
`score.py` computes deterministic filler counts and latency distributions,
and judges the semantic criteria (false starts, self-corrections, answered
questions, entity changes, removed/invented wording) with `claude -p`
against the raw ASR reference. Results of the shipping decision run are in
`RESULTS.md`.

`score-polish.py` is the scorer for the grammar/polish variants (e/f): it
tolerates rewording and instead judges meaning drift, entity/term fidelity,
contract violations, residual grammar errors, and over-polish. Results of
that experiment are in `RESULTS-polish.md`.
