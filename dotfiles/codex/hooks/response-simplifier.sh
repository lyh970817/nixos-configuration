#!/usr/bin/env bash
# Stop hook. Generate a short First Mate companion brief below the unchanged
# original response. Every failure path exits successfully without output so
# the brief generator cannot disturb the parent turn.

min_chars=1500

set -uo pipefail

input="$(cat)" || exit 0
message="$(jq -r '.last_assistant_message // empty' <<<"$input" 2>/dev/null)" || exit 0
[ -n "$message" ] || exit 0
[ "${#message}" -ge "$min_chars" ] || exit 0

prompt_file="${CODEX_HOME:-$HOME/.codex}/response-simplifier.md"
[ -r "$prompt_file" ] || exit 0

brief_file="$(mktemp)" || exit 0
trap 'rm -f "$brief_file"' EXIT

# --ignore-user-config keeps global AGENTS.md and mutable base settings out of
# the context. --disable hooks is the recursion guard for project and plugin
# hooks. The child is read-only, ephemeral, and does not need a Git checkout.
if ! printf '<message>\n%s\n</message>' "$message" | timeout 120 codex exec \
  --ignore-user-config \
  --disable hooks \
  --ephemeral \
  --skip-git-repo-check \
  --sandbox read-only \
  --model gpt-5.4 \
  --config 'approval_policy="never"' \
  --config 'model_reasoning_effort="medium"' \
  --output-last-message "$brief_file" \
  "$(<"$prompt_file")" \
  >/dev/null 2>&1; then
  exit 0
fi

brief="$(<"$brief_file")" || exit 0
[ -n "${brief//[[:space:]]/}" ] || exit 0

jq -n --arg brief "$brief" '{systemMessage: $brief}'
