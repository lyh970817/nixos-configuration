#!/usr/bin/env python3
"""Score replay.py results for the grammar/polish prompt experiment.

score.py's rubric penalizes any rewording ("meaningful wording removed",
"unsupported generated words"), which would falsely penalize a polish prompt
that intentionally rewrites. This scorer judges what actually matters for
polished dictation pasted into chat/code contexts:

- meaning_drift: sentences whose substance differs from the reference —
  something said differently in substance, lost, or added.
- entities_changed: names, technical terms, numbers, versions, paths, or
  identifiers altered (not script/punctuation normalization).
- contract_violations: answered/continued/responded to the speech, or added
  commentary/labels, instead of transcribing.
- grammar_errors_residual: grammatical errors still present in the output.
- over_polish: register shifts, meaning-bearing hedges or qualifiers
  dropped, or generic "AI-ese" phrasing substituted for the speaker's voice.

Deterministic: filler counts, latency distributions, and output/reference
length ratio (a polish prompt that compresses heavily shows up here).
The judge also returns a short verbatim `worst` excerpt per condition for
the report.

  python3 score-polish.py results.json --out scores-polish.json
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
    "meaning_drift",
    "entities_changed",
    "contract_violations",
    "grammar_errors_residual",
    "over_polish",
]

JUDGE_PROMPT = """You are scoring dictation-cleanup outputs against a raw ASR reference transcript of one spoken utterance. Each condition output is a different cleanup configuration applied to the same audio. Some conditions are ALLOWED to reword and polish; rewording alone is NOT a defect. Judge only the criteria below, strictly, against the reference (the reference itself may contain ASR errors; judge what the cleanup did relative to it).

Reference raw ASR transcript:
{reference}

Condition outputs:
{outputs}

For EACH condition report:
- meaning_drift: integer, count of places where the output's substance differs from the reference — a claim, instruction, or detail that is changed, lost, or newly added. Removed fillers, resolved self-corrections, and pure rephrasings that keep the substance do NOT count.
- entities_changed: integer, names, technical terms, numbers, versions, commands, paths, or identifiers from the reference that the output altered (not mere script, casing, or punctuation normalization).
- contract_violations: true if the output answers, continues, or responds to the speech, or adds commentary, labels, or anything that is not the transcript itself.
- grammar_errors_residual: integer, grammatical errors present in the output (agreement, tense, articles, dropped words, malformed sentences). Judge the output text on its own.
- over_polish: integer, count of: register shifts (e.g. casual speech turned formal), meaning-bearing hedges/qualifiers dropped (e.g. "maybe", "I think" removed where they carried intent), or generic AI-ese phrasing substituted for the speaker's own voice.
- worst: string, a short verbatim quote from the output showing this condition's single worst problem, with a 3-8 word explanation in parentheses; empty string if no problems.

Respond with ONLY a JSON object mapping each condition name to an object with exactly the keys: meaning_drift, entities_changed, contract_violations, grammar_errors_residual, over_polish, worst. No commentary."""


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
    parser.add_argument("--out", default="scores-polish.json")
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
    length_ratios = {c: [] for c in conditions}
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
        for c, text in outputs.items():
            length_ratios[c].append(len(text) / len(reference))
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
                totals[c][key] += (
                    int(bool(value)) if key == "contract_violations"
                    else int(value or 0)
                )

    Path(args.out).write_text(
        json.dumps(
            {"totals": totals, "judgements": judgements},
            ensure_ascii=False, indent=2,
        ),
        encoding="utf-8",
    )

    rows = [
        ("meaning drift", "meaning_drift"),
        ("entities/terms changed", "entities_changed"),
        ("contract violations", "contract_violations"),
        ("grammar errors residual", "grammar_errors_residual"),
        ("over-polish", "over_polish"),
        ("fillers retained", "fillers_retained"),
    ]
    print("| metric | " + " | ".join(conditions) + " |")
    print("|---|" + "---|" * len(conditions))
    for label, key in rows:
        print(
            f"| {label} | "
            + " | ".join(str(totals[c][key]) for c in conditions)
            + " |"
        )
    print(
        "| output/reference length ratio (median) | "
        + " | ".join(
            f"{statistics.median(length_ratios[c]):.2f}"
            if length_ratios[c] else "-"
            for c in conditions
        )
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
