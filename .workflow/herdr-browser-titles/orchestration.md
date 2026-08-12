# Orchestration

One owner handles discovery, design, implementation, tests, review, and revision so protocol and state-machine decisions remain coherent.

1. Inspect the repository's Herdr, Home Manager, systemd, secret, and managed-Codex-hook conventions.
2. Define the event/command boundary and persistent ownership state.
3. Implement the coordinator, enqueue client, CLI, module wiring, browser bindings, and managed hooks.
4. Add deterministic fake Unix-socket and fake HTTP coverage; never address the active server or real DashScope endpoint.
5. Stage and commit the scoped change before running standalone validation, per repository policy.
6. Run focused tests and static/config checks, revise in a follow-up commit if necessary, and report exact evidence upward.

Branching rules:

- Protocol uncertainty is resolved from installed/package source or fixtures, without a live control command.
- API/network uncertainty is resolved with fake HTTP; a real request requires a parent decision.
- Any failure in title generation or rename preserves the last/fallback title and never affects the agent hook's success.
- Manual tab renames pin; only an explicit `auto` or `claim` command re-enables automatic ownership.
