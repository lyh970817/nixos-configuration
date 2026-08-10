#!/usr/bin/env bash
# Stop hook. Takes the turn's finished assistant message, has a nested model
# rewrite it into plain English, and shows the rewrite under the
# original. `systemMessage` is the only stdout channel that reaches the user;
# plain stdout/stderr on exit 0 are discarded, and `additionalContext` or a
# blocking decision would go to the model instead. Never blocks: every failure
# path exits 0 with no output, so a broken rewriter cannot disturb the session.

# Messages shorter than this many characters are left alone, without spawning
# the nested call at all. That call costs 11-43s of wall time and buys nothing
# on a one-line answer.
#
# The threshold is not about compression, and length is not a goal here: the
# rewrite is meant to unpack. Measured on 41 real messages from this project,
# it returns ~152% of the original length. What the call buys is the sort into
# one of two shapes -- a status report, or a decision with its options and the
# recommendation -- plus a short labelled summary. That only pays when the
# input carries enough distinct material to fill the sections, which at 1500
# chars and above it does: 5.4 of 5.5 sections filled on average, empty-state
# lines rare.
#
# 1500 is inherited from the earlier, compression-based derivation and has NOT
# been revalidated against this one. The corpus was built at >=1500 chars, so
# it holds no evidence at all about what happens below the line.
#
# Sample sizes differ by measurement, and only these apply to this prompt:
# length and shape-selection accuracy are n=41; the blind retention comparison
# against the previous prompt is n=21, an unbiased half of the same corpus,
# cut short for quota reasons.
#
# Decision coverage -- the share of things waiting on the reader that reach the
# `**Summary**` -- was measured on a rebuilt 41-message corpus (81 decisions in
# 37 cases, ground truth and grading both by a nested blind opus-5 judge). Two
# noise floors were measured there and both matter when reading any result:
# regrading the same outputs moves the score by ~2.5 points, and regenerating
# the same prompt moves it by ~2.4. Differences smaller than that are not
# findings. What moved coverage was recognising decisions in `Your call`, not
# summary-space rules; ~7 of 9 losses never reached the section at all.
#
# Tune by editing this number: the hook reaches ~/.config/claude as an
# out-of-store symlink, so an edit is live with no rebuild.
min_chars=1500

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
# and the child burns thousands of output tokens and most of a minute before it
# writes anything. With it, 41 measured calls ran 11-43s, median 20s. Do not
# add --effort; any level re-enables thinking.
#
# The <message> wrapper is a content/instruction boundary the prompt refers to
# by name. Measured: an undelimited message that reads like a spec — one about
# this rewriter's own rules — made the child answer conversationally ("I'm
# Claude, I can't test that for you") instead of rewriting, and that reply is
# what the user would have seen. Wrapped, the same input rewrites correctly.
# Keep the tags and the prompt's first paragraph in step.
rewrite="$(
  printf '<message>\n%s\n</message>' "$message" | MAX_THINKING_TOKENS=0 timeout 120 claude \
    --safe-mode \
    --model claude-sonnet-5 \
    --system-prompt-file "$prompt_file" \
    --tools "" \
    -p 2>/dev/null
)" || exit 0

[ -n "${rewrite//[[:space:]]/}" ] || exit 0

jq -n --arg rewrite "$rewrite" '{systemMessage: $rewrite}'
