---
name: session-handoff
description: Hand the current work to another interactive Codex session in an adjacent Herdr pane or through an exact manual launch command. Use only when the user explicitly invokes $session-handoff or explicitly asks to hand off, continue in another Codex session, resume a named session, or fork a named session.
---

# Session Handoff

Prepare a compact continuation briefing, then launch the selected Codex session
with the orchestrator profile and unrestricted permissions. Do not depend on or
invoke the separate Herdr skill; the bundled helper contains the narrow Herdr
workflow needed here.

## Choose the mode

- `fresh` (default): start a new thread with no retained session history.
- `resume <SESSION_ID>`: reopen the same thread with its existing history.
- `fork <SESSION_ID>`: start a new thread that copies the selected thread's
  existing history.

Require an explicit session ID for `resume` and `fork`. If it is missing, ask
for it. Never substitute `--last` or choose from the interactive picker.

Use the current checkout and physical current directory by default. Use a
dedicated worktree only when the user explicitly asks to keep both sessions
working concurrently. For that concurrent handoff:

- First create the worktree — `git worktree add` with a new descriptive branch
  from HEAD — and pass its path as `--cwd` to the launch helper.
- The briefing must tell the receiving orchestrator: integrate its agents'
  branches only into that worktree; never merge into master, never push; when
  done, report back, then stop. Under Herdr it reports by prompting the calling
  agent with `herdr agent prompt` — name the calling agent in the briefing;
  otherwise, or on Herdr failure, it writes a ready report (branch name,
  worktree absolute path, what was merged, anything unresolved) to
  `~/.local/state/session-handoff/<name>.md`, creating the directory if needed.
- "Stop doing task work" below applies to control-transfer handoffs. In a
  concurrent handoff the original session stays in charge and, on the ready
  signal, merges the branch and cleans up the worktree.

## Write the briefing

Before launching anything, write a concise Markdown briefing containing:

- objective and current state;
- decisions already made and important rejected approaches;
- constraints and user preferences;
- repository, physical working directory, branch, and short Git status;
- relevant files and artifacts with absolute paths;
- unresolved items and the exact first action for the receiving session.

Summarize; do not dump the transcript. Redact credentials, tokens, private keys,
and other secrets. Create the draft with mode `0600` in the OS temporary
directory. A suitable sequence is `umask 077`, `mktemp
"${TMPDIR:-/tmp}/codex-handoff.XXXXXX.md"`, then write the briefing into the
returned path.

## Launch

Run the bundled helper directly; do not route it through the broad Herdr skill:

```sh
python3 "${CODEX_HOME:-$HOME/.codex}/skills/session-handoff/scripts/launch_handoff.py" \
  --mode fresh \
  --cwd "$(pwd -P)" \
  --consume-briefing \
  --briefing-file "$briefing_path"
```

For the other modes, replace `fresh` with `resume` or `fork` and append
`--session-id "$session_id"`.

Always pass `--consume-briefing` for the disposable temp draft created above.
The helper first makes its own mode-`0600` copy, then removes only that explicitly
supplied draft. Without the flag it never removes the caller's file. The copied
briefing is retained for manual fallback or Herdr failure recovery. A successful
Herdr prompt removes it immediately; the manual command tells the receiving
session to remove it after reading.

The helper always launches Codex with `--profile orchestrator` and
`--dangerously-bypass-approvals-and-sandbox`. Under Herdr it:

1. reads the caller layout using the explicit `HERDR_PANE_ID`;
2. splits that pane beside or below it with the same cwd and `--no-focus`;
3. starts a uniquely named Codex agent in the new pane;
4. submits the briefing separately with `herdr agent prompt --wait`;
5. focuses the receiving agent only after the prompt is accepted.

Outside Herdr, it does not control tmux or Herdr. It preserves the briefing in a
secure OS temporary file and prints the exact manual Codex command for the
selected mode.

If a Herdr split succeeds but a later operation fails, leave the pane intact.
Report the pane ID, agent name, briefing path, and error so the user can recover
manually. Do not delete the pane.

After a successful handoff, report the selected mode and receiving pane/agent,
then stop doing task work in the original session.
