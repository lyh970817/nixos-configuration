#!/usr/bin/env bash
# MessageDisplay hook. Takes an assistant message as it is being displayed, has
# a nested model rewrite it into plain English, and appends the rewrite to the
# message body under a divider.
#
# Ported from a Stop hook. `systemMessage` is the only user-visible channel a
# Stop hook has, and it renders the rewrite as a dim, indented `Stop says:`
# attachment with markdown left unparsed -- `**Summary**` reaches the screen
# with its asterisks. `displayContent` *is* the assistant message body, so the
# same text renders at body contrast with headings, lists and inline code
# formatted. That rendering difference is the whole reason for the port;
# nothing about the rewrite itself changed.
#
# The event fires once per streamed chunk of one message, carrying
# `.message_id` (groups the chunks), `.index` (chunk order), `.final` (true on
# the last one) and `.delta` (that chunk's fragment, NOT cumulative). Every
# delta is buffered to disk under its message id and only the final chunk calls
# the model, once the whole message is known.
#
# Two consequences of the channel, both intended:
#
#   - This runs on every assistant message, not only the last one of a turn.
#     Nothing in the event says whether more messages follow, so there is no
#     Stop-equivalent to gate on. The length threshold below is what keeps that
#     from being expensive.
#   - The final chunk's text is held on screen for as long as the nested call
#     takes (11-43s measured, see below). Earlier chunks have already streamed;
#     append mode never suppresses them.
#
# FAIL-OPEN CONTRACT: every failure path -- no jq, unparseable input, missing
# prompt file, model down, timeout, empty rewrite -- exits 0 with no output,
# which makes Claude Code display the original delta unchanged. A display hook
# must never be able to swallow an assistant message; this is the property to
# preserve above all others when editing this file.

# Messages shorter than this many characters are left alone, without spawning
# the nested call at all. That call costs 11-43s of wall time and buys nothing
# on a one-line answer.
#
# The threshold is not about compression, and length is not a goal here: the
# rewrite is meant to unpack. Measured on 41 real messages from this project,
# it returns ~152% of the original length. What the call buys is the sort into
# one of three shapes -- a status report, a decision with its options and the
# recommendation, or a plain-prose answer to a question -- and, for the first
# two, a short labelled summary. That only pays when the input carries enough
# distinct material to fill the sections, which at 1500 chars and above it
# does: 5.4 of 5.5 sections filled on average, empty-state lines rare. The
# corpus predates the Answer shape, so it says nothing about that branch.
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
# The corpus was measured on whole messages, so the gate counts whole messages
# here too.
#
# Tune by editing this number: the hook reaches ~/.config/claude as an
# out-of-store symlink, so an edit is live with no rebuild.
min_chars=1500

set -uo pipefail

# Every abandoned path lands here. Exit 0 with nothing on stdout is the
# documented "display the original delta" answer, and it is also what a crash
# or a timeout produces, so the contract holds even for paths not written here.
pass_through() { exit 0; }

# The divider under which the rewrite is appended. A markdown `---` is rendered
# literally by the message renderer, so the rule is drawn rather than marked up.
separator=$'\n\n────────────────────────\n\n'

command -v jq >/dev/null 2>&1 || pass_through

input="$(cat)" || pass_through
[ -n "$input" ] || pass_through

message_id="$(jq -r '.message_id // empty' <<<"$input" 2>/dev/null)" || pass_through
[ -n "$message_id" ] || pass_through
session_id="$(jq -r '.session_id // "nosession"' <<<"$input" 2>/dev/null)"
[ -n "$session_id" ] || session_id="nosession"
index="$(jq -r '(.index // 0) | tostring' <<<"$input" 2>/dev/null)"
case "$index" in '' | *[!0-9]*) index=0 ;; esac
final="$(jq -r '.final // false' <<<"$input" 2>/dev/null)"

buffer_root="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/claude-response-simplifier"
mkdir -p "$buffer_root" 2>/dev/null || pass_through

# A message whose final chunk never arrives -- interrupted turn, killed hook,
# crash -- leaves its parts behind, and nothing else would ever collect them.
# Sweep message directories untouched for half an hour, then the session
# directories they empty out.
find "$buffer_root" -mindepth 2 -maxdepth 2 -type d -mmin +30 -exec rm -rf {} + 2>/dev/null
find "$buffer_root" -mindepth 1 -maxdepth 1 -type d -empty -mmin +30 -exec rmdir {} + 2>/dev/null

message_dir="$buffer_root/$session_id/$message_id"
mkdir -p "$message_dir" 2>/dev/null || pass_through
part="$message_dir/$(printf '%08d' "$index").part"

# `jq -j` so the fragment is stored byte-exact, with no newline added.
jq -j '.delta // ""' <<<"$input" >"$part" 2>/dev/null || pass_through

# Append mode: non-final chunks stream through untouched, so a message is never
# held back or blanked while it is still arriving.
[ "$final" = "true" ] || pass_through

discard_buffer() { rm -rf "$message_dir" 2>/dev/null; }

message="$(cat "$message_dir"/*.part 2>/dev/null)" || { discard_buffer; pass_through; }
[ "${#message}" -ge "$min_chars" ] || { discard_buffer; pass_through; }

prompt_file="${CLAUDE_CONFIG_DIR:-$HOME/.config/claude}/response-simplifier.md"
[ -r "$prompt_file" ] || { discard_buffer; pass_through; }

# --safe-mode is the recursion guard: the child inherits CLAUDE_CONFIG_DIR and
# would otherwise load this same hook. That matters more on MessageDisplay than
# it did on Stop -- the child emits assistant messages of its own, so an
# unguarded child would fire this hook on its own output and fork again, once
# per message rather than once per turn. Safe mode also keeps CLAUDE.md out of
# the child, which is intended: the rewriter is deliberately context-free. Not
# --bare: it demands ANTHROPIC_API_KEY and ignores this machine's subscription
# OAuth.
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
)" || { discard_buffer; pass_through; }

[ -n "${rewrite//[[:space:]]/}" ] || { discard_buffer; pass_through; }

# Only this chunk's own delta is replaced; earlier chunks are already on
# screen. Emitting anything less than the final delta here would drop the end
# of the message, so it is carried through verbatim ahead of the divider.
final_delta="$(cat "$part" 2>/dev/null)"
discard_buffer

jq -n --arg delta "$final_delta" --arg separator "$separator" --arg rewrite "$rewrite" \
  '{hookSpecificOutput: {hookEventName: "MessageDisplay",
                         displayContent: ($delta + $separator + $rewrite)}}' \
  || pass_through
