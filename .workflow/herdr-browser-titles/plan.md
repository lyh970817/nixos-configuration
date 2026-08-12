# Herdr browser tabs and dynamic titles

Goal: Replace persistent numeric tab slots with browser-style navigation and asynchronously maintain semantic Herdr tab titles for Claude and Codex.

Success criteria:

- Native `Ctrl+T`, `Ctrl+Tab`, and `Ctrl+Shift+Tab` navigation with immediate unnamed tab creation.
- One user coordinator discovers named Herdr servers, mirrors Claude OSC titles, and generates dynamic Codex titles through DashScope without blocking agents.
- Ownership, epochs, manual pins, reconnects, stale-result rejection, secret handling, and operator reclaim commands are deterministic.
- Managed Codex hooks enqueue `SessionStart` and `UserPromptSubmit` events locally and return immediately.
- Fake-server and fake-HTTP tests exercise the behavioral contract without touching the active Herdr session or the real Qwen endpoint.

Constraints: preserve unrelated root-checkout edits; work only on `herdr-browser-titles`; do not rebuild, deploy, merge, push, or call the real API; commit before standalone validation.

Risks: accidental active-session mutation, credential disclosure, stale asynchronous renames, and undocumented Herdr wire assumptions. Mitigations are fake protocol tests, redaction/no logging, per-owner epochs and sequences, and cosmetic-only failure behavior.

Approval: source changes and local commits are approved. Real Qwen calls, activation, merging, peer sync, and rebuild are outside this worker's authority.

Artifact path: `.workflow/herdr-browser-titles/`.

Reusable artifacts: keep this small run artifact in the change because it records the cross-component safety contract; do not store transcripts, secrets, or generated logs.
