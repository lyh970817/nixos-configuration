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
arguments and will swallow a trailing prompt.

```sh
claude --bg "<briefing>" --model <this session's model> \
  --append-system-prompt-file ~/.config/claude/orchestrator-opus.md \
  -w <name>
```

Use `orchestrator-fable.md` for a Fable session. `--append-system-prompt-file`
is required: a `--bg` session inherits nothing from this one.

`-w <name>` create-or-reuses `.claude/worktrees/<name>` on branch
`worktree-<name>`, branched from the local HEAD (`worktree.baseRef: "head"`).
Pick a fresh, descriptive name. The new session starts inside this worktree,
and it is the integration target for that session's subagents. Omit `-w` only
when the handoff will not change the repository.

## Briefing

The prompt is the new session's entire context. State what it is picking up,
the decisions and dead ends that the files do not show, and the first concrete
action. Include absolute paths and branch names. Do not paste transcript.

For a worktree handoff the briefing must also state:

- It is an orchestrator handed work by another session, so repo policy forbids
  it merging into master, rebuilding, or pushing.
- It merges its subagents' branches into its own worktree checkout. Give the
  worktree's absolute path explicitly — its merge agent otherwise defaults to
  the main checkout and lands the work in the wrong tree.
- Its last action, once everything is merged and committed on
  `worktree-<name>`, is to write a ready report — branch name, worktree
  absolute path, what was merged, anything unresolved — to
  `~/.local/state/session-handoff/<name>.md` (creating the directory if
  needed), then stop.

## Await and merge

Watch for the ready report with a background poll, re-armed if it expires —
or check it when the user asks:

```sh
until [ -f ~/.local/state/session-handoff/<name>.md ]; do sleep 15; done
```

When it appears, read it, then organize the merge in the main checkout: merge
`worktree-<name>` into master and deliver per repo policy. Cleanup, only once
fully merged:

```sh
git worktree unlock .claude/worktrees/<name>
git worktree remove .claude/worktrees/<name>
git branch -d worktree-<name>
rm ~/.local/state/session-handoff/<name>.md
```

## Managing

```sh
claude agents --json          # live sessions with pids; --all, --cwd DIR
kill <pid>                    # stop one
rm -rf ~/.config/claude/jobs/<shortId>   # or the daemon respawns it
```

`claude attach`, `claude logs`, and `claude stop` do not exist despite the
`--bg` banner; they are parsed as prompts and start new sessions. Attach through
the `claude agents` TUI.

The ready report is the one channel back to this session; everything else
still goes through `claude agents`. Tell the user where the work is happening.
