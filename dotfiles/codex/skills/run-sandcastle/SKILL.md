---
name: run-sandcastle
description: Run this repo's local Sandcastle Codex workflows for GitHub issues, including ready-for-agent issue processing, PR publishing and merging, simple-loop, sequential-reviewer, parallel-planner, and parallel-planner-with-review.
---

# Run Sandcastle

Use this skill when asked to run Sandcastle, process `ready-for-agent` issues,
run issue agents, run a batch of issues, or use the local Sandcastle
planner/reviewer templates.

## Preflight

Work from the repository root. Before reading workflow files or launching any
flow, verify the checkout is clean and synchronized with its upstream:

```sh
git fetch --prune
git status --short
git status --branch --porcelain=v1
```

Abort without running Sandcastle if:

- `git fetch --prune` fails;
- `git status --short` prints any file changes;
- branch status shows divergence, no upstream, or unknown upstream state, such
  as `[ahead N, behind M]` or no `...origin/<branch>` marker.

If the branch is only ahead of upstream, push first:

```sh
git push
git status --short
git status --branch --porcelain=v1
```

If the branch is only behind upstream, pull first:

```sh
git pull --ff-only
git status --short
git status --branch --porcelain=v1
```

Proceed only if the push or pull succeeds, `git status --short` is empty, and
the branch status no longer shows ahead, behind, divergence, or unknown
upstream state. If the push/pull fails or the branch is still not clean and
synchronized, abort, show the exact status output, and ask the user to resolve
the branch state.

After preflight passes, read `package.json`, `.sandcastle/main.mts`, and the
selected workflow files. Read `.sandcastle/options.mts`,
`.sandcastle/codex.mts`, and `.sandcastle/list-ready-issues.mts` when checking
CLI flags, model settings, or issue selection.

Do not look for `.sandcastle/README.md`, old custom runner docs, old
`.sandcastle/runs/<run-id>/summary.json` outputs, or an `## Agent Brief`
section. The workflows use the full GitHub issue body produced by `$to-issues`,
especially `## What to build`, `## Acceptance criteria`, and `## Blocked by`.

## Commands

The top-level selector accepts these flow names:

```sh
npm run sandcastle -- blank
npm run sandcastle -- simple-loop
npm run sandcastle -- sequential-reviewer
npm run sandcastle -- parallel-planner
npm run sandcastle -- parallel-planner-with-review
```

Convenience scripts also exist:

```sh
npm run sandcastle:blank
npm run sandcastle:simple-loop
npm run sandcastle:sequential-reviewer
npm run sandcastle:parallel-planner
npm run sandcastle:parallel-planner-with-review
```

Use `--max-iterations <n>` to override a workflow's default outer iteration
count:

```sh
npm run sandcastle -- parallel-planner-with-review --max-iterations 1
```

The parser also accepts `--max-iteration` and `--maxIterations`, but use
`--max-iterations` in examples. Running `npm run sandcastle` with no flow only
prints usage.

The current runner does not support old custom flags such as `--issue`,
`--issues`, `--schedule`, `--label`, `--ignore-blockers`, `--dry-run`,
`--plan-only`, `--model`, `--effort`, or `--network-access`.

## Choose A Flow

- `simple-loop`: one autonomous worker, no separate review phase. It processes
  one actionable `ready-for-agent` issue per iteration on `sandcastle/issue-<ID>`
  and may publish/merge a PR. Default: 3 iterations.
- `sequential-reviewer`: one issue branch per outer iteration, implementer then
  reviewer then publisher. Branches are `sandcastle/sequential-reviewer/<time>`;
  the implementer writes `.sandcastle/selected-issue.json`. Default: 10
  iterations.
- `parallel-planner`: planner selects dependency-safe issues, implementers run
  in parallel on deterministic `sandcastle/issue-<ID>` branches, then a
  publisher handles completed branches. Default: 10 iterations.
- `parallel-planner-with-review`: same as `parallel-planner`, but each issue
  pipeline runs implementer then reviewer before publishing. This is usually
  the default for parallel Sandcastle work with review.
- `blank`: upstream scaffold only; not wired for this repo's issue workflow.

Before launching an issue-oriented flow, state that it may create commits, push
branches, open/reuse PRs, merge PRs through GitHub, delete remote branches,
close issues through PR closing keywords, leave blocker comments, and
fast-forward the local base branch. Treat a request to run such a flow as
permission for that documented behavior after stating it. If the user asks only
to inspect, plan, or dry-run, do not launch these workflows; there is no dry-run
mode.

## Runner Facts

- The repo has `.sandcastle/blank/`, `.sandcastle/simple-loop/`,
  `.sandcastle/sequential-reviewer/`, `.sandcastle/parallel-planner/`, and
  `.sandcastle/parallel-planner-with-review/`.
- `.sandcastle/codex.mts` defaults to `codex("gpt-5.5", { effort: "high" })`
  and injects profile `mattpocock`.
- The workflows use `noSandbox()`, relying on the host R, GitHub CLI, Git, and
  Codex setup.
- `.sandcastle/list-ready-issues.mts` lists open `ready-for-agent` issues and
  includes `hasSubIssues`, `parentIssueId`, and
  `linkedImplementationIssueIds`.
- PRD containers are context only. Do not implement or close them.
- Implementation/review prompts use R package verification, not npm
  typecheck/test commands.
- Publication means GitHub PR publication and GitHub PR merge. Do not merge
  Sandcastle branches locally as a fallback.

Issue closure should happen through merged PR closing keywords, not
`gh issue close`. Parent PRDs should receive a closing keyword only after all
linked implementation issues are closed or will be closed by PRs in the run.
Do not change labels unless the user explicitly asks.

## Git Config Workaround

Sandcastle's no-sandbox setup may run:

```sh
git config --global --add safe.directory "<repo-path>"
```

If the normal global Git config path is read-only, scope `GIT_CONFIG_GLOBAL` to
a writable temporary file for the Sandcastle invocation:

```sh
tmp_git_config="$(mktemp)"
GIT_CONFIG_GLOBAL="$tmp_git_config" npm run sandcastle -- parallel-planner-with-review
exit_code=$?
rm -f "$tmp_git_config"
exit "$exit_code"
```

Use the selected flow name in place of `parallel-planner-with-review`. In zsh,
use `exit_code`, not `status`.

## Failure Policy

Do not run verification requiring live Qualtrics credentials. Prefer fixture,
snapshot, local, or recorded-cassette tests.

Do not pass Codex sandbox flags through Sandcastle commands; this setup already
uses Sandcastle's `noSandbox()` provider.

After launching Sandcastle, wait only on the Sandcastle command's own process
handle until it exits. Do not inspect logs, Git state, worktrees, branches,
commits, files, GitHub PRs, GitHub issues, child processes, or any other
observable run state while the process is still running.

If a run fails, times out, hangs, or appears stuck, do not fix the setup,
prompts, code, branches, or issues in the same thread unless the user explicitly
asks. Inspect observable run state and report it.

If the user asks for one specific issue, note that there is no one-issue CLI
flag. Ask whether to run the queue-based flow, or temporarily edit the relevant
prompt only if explicitly requested.

## After The Run

Do not poll logs, inspect Git state, inspect worktrees, check GitHub state,
inspect files, inspect child processes, or otherwise probe run progress while
Sandcastle is running. Wait for the Sandcastle process itself to exit with
completion or failure before checking anything. The only allowed action during
the run is waiting for process output or process termination through the
existing Sandcastle command/session. If it does not exit after a reasonable
point and appears stuck, stop waiting, then collect evidence and report the
hang.

Only after the Sandcastle process exits, inspect:

```sh
git status --short
git branch --list 'sandcastle/*'
git worktree list
git log --oneline --decorate -20
ls -lt .sandcastle/logs
```

Read relevant final logs under `.sandcastle/logs/`. If PR publication was
possible or expected, also inspect GitHub state:

```sh
gh pr list --state all --limit 20 --json number,title,state,headRefName,baseRefName,mergedAt,url
gh issue list --state open --label ready-for-agent --limit 100
```

Summarize: overall status; flow and `--max-iterations` override if used; issues
and branches mentioned; commits created; PRs opened/reused/left open/merged;
whether the local base branch fast-forwarded; issues closed by PR keywords;
failed or blocked work with log evidence; and verification gaps.
