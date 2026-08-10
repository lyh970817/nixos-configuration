---
name: session-handoff
description: Use when the user wants to hand a set of tasks to a fresh Claude Code session rather than continue in this one — a context handoff to an independent instance, not a subagent.
---

# Session handoff

Launch an independent session with a briefing, so the new work starts without
this conversation's history. Design notes: `docs/session-handoff.md` in
`~/.nixos-config`.

## Launch

Prompt first — `-w`, `--add-dir`, and the tool flags take optional or variadic
arguments and will swallow a trailing prompt. Same directory, no worktree:

```sh
claude --bg "<briefing>" --model <this session's model> \
  --append-system-prompt-file ~/.config/claude/orchestrator-opus.md
```

Use `orchestrator-fable.md` for a Fable session. `--append-system-prompt-file`
is required: a `--bg` session inherits nothing from this one.

Add `-w <name>` only when the user asks for a worktree. It create-or-reuses
`.claude/worktrees/<name>` on branch `worktree-<name>`, branched from
the local HEAD, as configured by `worktree.baseRef: "head"`.

## Briefing

The prompt is the new session's entire context. State what it is picking up,
the decisions and dead ends that the files do not show, and the first concrete
action. Include absolute paths and branch names. Do not paste transcript.

## Managing

```sh
claude agents --json          # live sessions with pids; --all, --cwd DIR
kill <pid>                    # stop one
rm -rf ~/.config/claude/jobs/<shortId>   # or the daemon respawns it
```

`claude attach`, `claude logs`, and `claude stop` do not exist despite the
`--bg` banner; they are parsed as prompts and start new sessions. Attach through
the `claude agents` TUI.

Nothing reports back to this session. Tell the user where the work is happening.
