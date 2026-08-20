# ADR 0001: Use a fresh execution for Stop-hook companion briefs

## Status

Accepted

## Date

2026-08-20

## Context

The Codex Stop hook adds a companion brief below a completed assistant response.
The completed response remains visible and authoritative; the brief exists only
to orient the reader. The [production prompt](../../dotfiles/codex/response-simplifier.md)
therefore treats the content inside its explicit `<message>` envelope as its sole
source. The [evaluation](../stop-hook-model-comparison.md) and
[retrospective](../stop-hook-prompt-optimization.md) document why this is a
single-artifact transformation rather than a summary of the conversation.

Programmatic `codex exec fork` is now technically available, so the earlier
choice of a fresh child is no longer forced by tooling. A fork, however,
continues an existing session and inherits its history. That history is
semantically irrelevant to the brief's contract and could contaminate the
result with facts, qualifications, or intent not present in the visible source.

The post-response Stop lifecycle supplies `last_assistant_message` in the hook
payload. A fork does not improve access to that value: the
[hook](../../dotfiles/codex/hooks/response-simplifier.sh) must still extract it
and pass it explicitly to the summarizer.

## Decision

Keep the Stop-hook summarizer as a fresh, ephemeral, payload-scoped `codex exec`
child. Do not use `codex exec fork` or otherwise inherit the parent
conversation's history.

Continue to pass only `last_assistant_message` inside the delimited source
envelope. Keep the child operation's model, reasoning effort, timeout,
read-only sandbox, approval policy, ephemerality, and output capture explicit.
Keep child hooks disabled to prevent recursion, and preserve fail-open behavior
so summarization failure cannot disturb the completed parent response.

## Consequences

- The brief remains reproducible from the one artifact the reader can see and
  verify as authoritative.
- Earlier conversation cannot silently resolve ambiguity, add facts, or change
  the meaning of the completed response.
- The summarization operation remains independently configurable and isolated
  from mutable user configuration and parent-session state.
- The completed response must contain enough context to support its own brief.
  If it does not, the summarizer must not recover missing context from history.
- A fresh child has startup cost, but forked history would not provide a
  contract-valid benefit that justifies the additional coupling.

## Alternatives

### Fork the parent session with full history

Rejected. History could help interpret pronouns or recover omitted context, but
that would turn the brief into a conversation-aware synthesis. It could then be
more informative than, or diverge from, the completed response it accompanies.
It would also couple a post-response display hook to the parent session's
identity and accumulated context without eliminating the explicit payload
handoff.

### Fork a bounded portion of recent history

Rejected for the same contract reason. A smaller inherited context is still a
second source, and choosing a turn boundary would introduce context-selection
semantics unrelated to the companion brief.

## Reconsideration

Reconsider this decision if programmatic fork gains a payload-scoped,
no-history mode with lifecycle, isolation, configuration, recursion-prevention,
and fail-open guarantees equivalent to the fresh child. Also reconsider it if
the product requirement changes from summarizing the completed assistant
response to producing a conversation-aware summary. Either change would alter
the design boundary on which this ADR depends.
