#!/usr/bin/env python3
"""Score replay.py results across prompt conditions.

Deterministic counts (vocal fillers, latency) are computed directly; the
semantic criteria from the experiment design (false starts retained,
self-corrections resolved, questions answered instead of transcribed,
entities changed, meaningful wording removed, unsupported generated words)
are judged per utterance by `claude -p` against the provider's raw ASR
transcript, with a strict JSON rubric. Emits a Markdown table.

  python3 score.py results.json --out scores.json
"""

import argparse
import json
import re
import statistics
import subprocess
import sys
from pathlib import Path

FILLER_RE = re.compile(
    r"\b(um+|uh+|uhm|erm|er|ah+|hmm+|mmm+)\b|[嗯呃]",
    re.IGNORECASE,
)

JUDGE_KEYS = [
    "false_starts_retained",
    "self_corrections_unresolved",
    "answered_instead_of_transcribed",
    "entities_changed",
    "meaningful_wording_removed",
    "unsupported_words",
]

JUDGE_PROMPT = """You are scoring dictation-cleanup outputs against a raw ASR reference transcript. The reference is the provider's verbatim speech recognition of one spoken utterance; each condition output is a different cleanup model configuration applied to the same audio.

Reference raw ASR transcript:
{reference}

Condition outputs:
{outputs}

For EACH condition, evaluate strictly against the reference (the reference itself may contain ASR errors; judge only what the cleanup did relative to it):
- false_starts_retained: integer, abandoned sentence starts / stutter fragments still present in the output.
- self_corrections_unresolved: integer, self-corrections (e.g. "X, wait no, Y", "X 不对 Y") where the output kept the superseded wording or the correction cue.
- answered_instead_of_transcribed: true if the output answers, continues, or responds to the speech instead of transcribing it.
- entities_changed: integer, names, numbers, versions, paths, or identifiers present in the reference that the output altered (not mere script/punctuation normalization).
- meaningful_wording_removed: integer, content-bearing words or phrases from the reference missing in the output (not fillers, repetitions, or superseded corrections).
- unsupported_words: integer, content-bearing words in the output with no support in the reference (not punctuation or casing).

Respond with ONLY a JSON object mapping each condition name to an object with exactly these keys: false_starts_retained, self_corrections_unresolved, answered_instead_of_transcribed, entities_changed, meaningful_wording_removed, unsupported_words. No commentary."""


def judge(reference, outputs):
    prompt = JUDGE_PROMPT.format(
        reference=reference,
        outputs="\n".join(
            f"[{name}]\n{text or '(empty output)'}\n"
            for name, text in outputs.items()
        ),
    )
    result = subprocess.run(
        ["claude", "-p", "--output-format", "text"],
        input=prompt,
        capture_output=True,
        text=True,
        timeout=300,
    )
    if result.returncode != 0:
        raise RuntimeError(f"claude -p failed: {result.stderr[:200]}")
    match = re.search(r"\{.*\}", result.stdout, re.DOTALL)
    if not match:
        raise ValueError(f"no JSON in judge output: {result.stdout[:200]}")
    return json.loads(match.group(0))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results")
    parser.add_argument("--out", default="scores.json")
    parser.add_argument("--no-judge", action="store_true")
    args = parser.parse_args()

    results = json.loads(Path(args.results).read_text(encoding="utf-8"))
    conditions = sorted(
        {k for entry in results.values() for k in entry if k != "duration_s"}
    )

    totals = {
        c: {key: 0 for key in JUDGE_KEYS} | {"fillers_retained": 0, "judged": 0}
        for c in conditions
    }
    latencies = {c: [] for c in conditions}
    judgements = {}

    for name, entry in sorted(results.items()):
        outputs = {}
        reference = ""
        for c in conditions:
            data = entry.get(c) or {}
            text = data.get("text")
            if text is None:
                continue
            outputs[c] = text
            if data.get("latency_ms"):
                latencies[c].append(data["latency_ms"])
            totals[c]["fillers_retained"] += len(FILLER_RE.findall(text))
            raw = (data.get("raw_asr") or "").strip()
            if len(raw) > len(reference):
                reference = raw
        if not outputs or not reference:
            continue
        if args.no_judge:
            continue
        try:
            verdict = judge(reference, outputs)
        except Exception as e:
            print(f"judge failed for {name}: {e}", file=sys.stderr)
            continue
        judgements[name] = verdict
        for c, scores in verdict.items():
            if c not in totals or not isinstance(scores, dict):
                continue
            totals[c]["judged"] += 1
            for key in JUDGE_KEYS:
                value = scores.get(key, 0)
                totals[c][key] += int(bool(value)) if key == "answered_instead_of_transcribed" else int(value or 0)

    Path(args.out).write_text(
        json.dumps({"totals": totals, "judgements": judgements}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    rows = [
        ("fillers retained", "fillers_retained"),
        ("false starts retained", "false_starts_retained"),
        ("self-corrections unresolved", "self_corrections_unresolved"),
        ("answered instead of transcribed", "answered_instead_of_transcribed"),
        ("entities changed", "entities_changed"),
        ("meaningful wording removed", "meaningful_wording_removed"),
        ("unsupported generated words", "unsupported_words"),
    ]
    print("| metric | " + " | ".join(conditions) + " |")
    print("|---|" + "---|" * len(conditions))
    for label, key in rows:
        print(
            f"| {label} | "
            + " | ".join(str(totals[c][key]) for c in conditions)
            + " |"
        )
    for label, fn in (
        ("commit->final median ms", statistics.median),
        ("commit->final p90 ms", lambda xs: sorted(xs)[max(0, int(len(xs) * 0.9) - 1)]),
    ):
        print(
            f"| {label} | "
            + " | ".join(
                str(round(fn(latencies[c]))) if latencies[c] else "-"
                for c in conditions
            )
            + " |"
        )
    print(
        "| utterances judged | "
        + " | ".join(str(totals[c]["judged"]) for c in conditions)
        + " |"
    )


if __name__ == "__main__":
    main()
