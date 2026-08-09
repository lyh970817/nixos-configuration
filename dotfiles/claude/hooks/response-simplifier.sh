#!/usr/bin/env bash
# Stop hook. Takes the turn's finished assistant message, has a cheap nested
# model rewrite it into plain English, and shows the rewrite under the
# original. `systemMessage` is the only stdout channel that reaches the user;
# plain stdout/stderr on exit 0 are discarded, and `additionalContext` or a
# blocking decision would go to the model instead. Never blocks: every failure
# path exits 0 with no output, so a broken rewriter cannot disturb the session.

# Messages shorter than this many characters are left alone, without spawning
# the nested call at all. That call costs 4-8s of wall time and buys nothing on
# a one-line answer. Tune by editing this number: the hook reaches
# ~/.config/claude as an out-of-store symlink, so an edit is live with no
# rebuild.
min_chars=600

set -uo pipefail

input="$(cat)" || exit 0

# `last_assistant_message` carries the finished message. Do not read
# `transcript_path`: at hook time the final message is not flushed to it yet.
message="$(jq -r '.last_assistant_message // empty' <<<"$input" 2>/dev/null)" || exit 0
[ -n "$message" ] || exit 0
[ "${#message}" -ge "$min_chars" ] || exit 0

prompt_file="${CLAUDE_CONFIG_DIR:-$HOME/.config/claude}/response-simplifier.md"
[ -r "$prompt_file" ] || exit 0

# --safe-mode is the recursion guard: the child inherits CLAUDE_CONFIG_DIR and
# would otherwise load this same Stop hook and spawn another child forever. It
# also keeps CLAUDE.md out of the child, which is intended — the rewriter is
# deliberately context-free. Not --bare: it demands ANTHROPIC_API_KEY and
# ignores this machine's subscription OAuth.
#
# --system-prompt-file replaces Claude Code's default system prompt, which is
# dead weight for a rewrite. MAX_THINKING_TOKENS=0 is what makes that pay off:
# measured, replacing the default prompt without it turns extended thinking on
# and the child spends ~6700 output tokens and 52-70s. With it the same call is
# 4-8s and ~200 output tokens. Do not add --effort; any level re-enables
# thinking and costs 50s+ again.
rewrite="$(
  printf '%s' "$message" | MAX_THINKING_TOKENS=0 timeout 120 claude \
    --safe-mode \
    --model claude-haiku-4-5-20251001 \
    --system-prompt-file "$prompt_file" \
    --tools "" \
    -p 2>/dev/null
)" || exit 0

[ -n "${rewrite//[[:space:]]/}" ] || exit 0

jq -n --arg rewrite "$rewrite" '{systemMessage: $rewrite}'
