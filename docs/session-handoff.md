# Session handoff skill (design)

Design for a planned Claude Code skill. This is a specification, not the skill.
All command behaviour below was measured on Claude Code 2.1.226.

## Purpose

Hand a distinct set of tasks to a **new, independent Claude Code session** instead
of continuing in the current one. The motivation is context hygiene: the new
session starts with no conversation history, only a briefing the parent writes.
It is not a subagent — it is a separate `claude` process with its own context,
transcript, and lifetime.

## Behaviour

1. Launches an independent instance with `claude --bg`, which lands in agent view.
2. Working directory defaults to the parent session's directory. No worktree.
3. A worktree is created only on explicit request, via `-w <name>`.
4. The new session must carry the same `--append-system-prompt` text as the
   parent. Hard requirement: the orchestrator instructions live in that flag.
   See "append-system-prompt inheritance" — it is **not** inherited, so the skill
   must pass it.
5. The initial prompt is a handoff briefing written by the parent.
6. Communication back to the parent is **out of scope in this version** (deferred,
   not unsupported).

## Command shapes

Default case — same directory, no worktree, prompt first:

```sh
claude --bg "<handoff briefing>" --append-system-prompt-file ~/.config/claude/orchestrator-opus.md
```

Worktree case — creates or reuses `.claude/worktrees/<name>` on branch
`worktree-<name>`:

```sh
claude --bg "<handoff briefing>" --append-system-prompt-file ~/.config/claude/orchestrator-opus.md -w handoff-auth
```

Inline variant, if the prompt text is not kept in a file:

```sh
claude --bg "<handoff briefing>" --append-system-prompt="<orchestrator text>"
```

`--append-system-prompt` and `--append-system-prompt-file` are mutually
exclusive; passing both is a hard error.

## The handoff briefing

The prompt is the entire context the new session gets. It should state:

- What it is picking up, in one or two sentences.
- Background the parent established that is not recoverable from the files
  (decisions taken, approaches already rejected and why, constraints).
- Concrete first action, so the session does not open by re-deriving the task.
- Relevant absolute paths, branch names, and any open questions to route back to
  the user rather than guess.

Do not paste transcript excerpts. The point of the handoff is that the history
does not travel.

## Managing sessions

```sh
claude agents --json              # list live sessions with pids; needs no TTY
claude agents --json --all        # include completed
claude agents --json --cwd DIR    # filter by directory
kill <pid>                        # stop a session
rm -rf ~/.config/claude/jobs/<shortId>   # otherwise the daemon may respawn it
```

Attaching to a live session goes through the `claude agents` TUI. A live bg
session refuses plain `--resume`; `--fork-session` branches a copy instead of
attaching.

Worktree cleanup — worktrees are created `locked`:

```sh
git worktree unlock .claude/worktrees/<name>
git worktree remove --force .claude/worktrees/<name>
```

## Known traps

- **`claude attach`, `claude logs`, `claude stop` do not exist**, despite being
  advertised in the `--bg` banner. Commander treats the unknown word as a prompt,
  so `claude logs <id>` starts a brand-new agentic session whose task is the
  literal string `logs <id>`. These must never appear in the skill.
- **Flag order.** `-w [name]`, `--allowedTools <tools...>`, `--tools`, and
  `--add-dir` take optional or variadic arguments and will swallow a trailing
  prompt. Put the prompt first, or use `=` forms. A `--bg` banner ending in
  `(idle — send a prompt to start)` means the prompt was eaten and nothing runs.
- **Worktree base ref.** With an origin present, a new worktree branches from
  `origin/<default>`, not local HEAD, because `worktree.baseRef` defaults to
  `fresh`. Uncommitted or unpushed parent work is not there.

## append-system-prompt inheritance

**OBSERVED: a `--bg` session does not inherit the parent's
`--append-system-prompt`.** Evidence, in order of strength:

1. Static inspection of the shipped bundle
   (`/nix/store/…-claude-code-2.1.226/bin/.claude-wrapped`). The background-spawn
   argv builder forwards only `replConfigArgv` — the set populated at startup
   from `--settings`, `--plugin-dir*`, `--add-dir`, `--mcp-config`,
   `--strict-mcp-config`, `--fallback-model`,
   `--allow-dangerously-skip-permissions`, `--disable-slash-commands`,
   `--channels`. `--append-system-prompt` is not in it. The parent's
   `appendSystemPrompt`/`agent`/`agents` are stashed separately in
   `forkReplayLaunchConfig` and re-emitted **only** when `keepParent` is set, i.e.
   on a fork (`--fork-session`), not on a plain background spawn.
2. No `state.json` under `~/.config/claude/jobs/*` contains
   `--append-system-prompt` in its `respawnFlags`; observed arrays hold
   `--reply-on-resume`, `--settings`, `--permission-mode`, `--model`.
3. A CLI `claude --bg` typed from a shell is a fresh process whose argv is
   exactly what was typed; there is no parent argv to inherit from.

Note the current interactive sessions on this machine do **not** pass
`--append-system-prompt` at all — `/proc/<pid>/cmdline` for the live `claude`
processes shows only `--settings`, `--dangerously-skip-permissions`, and
`agents`/`--resume`. So there is presently no live value to propagate; the
requirement is forward-looking.

Confirming live test, if ever needed: launch an interactive session with
`--append-system-prompt "MARKER=BANANA7"`, from inside it run
`claude --bg "State the marker from your system prompt, then stop."`, and read
the new job's transcript. Marker absent confirms the above.

### Both branches

- **If the flag were inherited**, the skill would do nothing special: `claude
  --bg "<briefing>"` and stop.
- **It is not inherited**, so the skill must pass it explicitly. That means the
  prompt text has to exist somewhere the skill can read at launch time.

Recommended either way: keep the text in a file —
`~/.config/claude/orchestrator-{opus,fable}.md`, out-of-store symlinks to
`dotfiles/claude/` — and have both the user's launcher
and this skill pass `--append-system-prompt-file <path>`. Reasons: the skill
never has to reconstruct or quote multi-line text; launcher and handoff cannot
drift; `/proc/<pid>/cmdline` scraping (fragile, and empty today) is unnecessary;
and edits to the text apply to the next session without touching either caller.
`appendSystemPrompt` is **not** a settings-file key at any scope, so a settings
file is not an alternative.

Implementation note: the skill must not modify the launcher, shell config, or any
Claude config. If the file does not exist, it should say so and fall back to
launching without the flag rather than inventing content.

## Deferred

- **Child-to-parent communication.** No result reporting, status callback, or
  message channel back to the launching session in this version. The parent
  learns nothing automatically; the user inspects the new session through
  `claude agents`. Revisit once a supported channel exists.
