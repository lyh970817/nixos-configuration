---
name: pull-request-ci
description: Make CI monitoring a mandatory part of every pull request. Use whenever you are about to open a pull request (`gh pr create`, draft or not), push new commits to a branch that has an open PR, mark a draft ready (`gh pr ready`), or are asked about a PR's status, "CI is failing", "checks are red", a failing GitHub Actions run or failing checks. Covers reproducing CI locally (including fork PRs where secrets are empty), watching `gh pr checks` to conclusion, classifying failures with log evidence, and reporting CI state with the PR.
---

# Pull request CI

A PR is not done when it is opened; it is done when its checks have concluded
and every failure is explained. Reporting a PR as "open" while all its checks
were red, unseen, is the failure this skill exists to prevent.

1. **Before opening or pushing, run what CI runs.** Read
   `.github/workflows/*.y*ml` for the jobs, the matrix, the exact test command
   and the `env:` it sets. Run that command locally the same way where
   feasible, on the files you changed. On a pull request from a **fork**,
   `${{ secrets.* }}` are empty: reproduce with those variables unset or
   empty, not with your local credentials, and expect credential-dependent
   tests to fail or skip. Know this before CI tells you.
2. **After `gh pr create` or any push to a PR branch, watching CI is
   mandatory.** The task is not complete until every check has concluded.
   - Immediately: `gh pr checks <num> --repo <owner/repo>` (checks can take a
     minute to register; re-run once if the list is empty).
   - Then wait for conclusions with
     `gh pr checks <num> --repo <owner/repo> --watch --interval 60`, run with
     the Bash tool's `run_in_background` (checks often take 15+ minutes; the
     foreground limit is 10), or `gh run watch <run-id> --repo <owner/repo>`.
   - Never poll in a tight loop. Never declare the PR done while checks are
     pending. If you must answer the user first, say explicitly that checks
     are still running and that you will report when they conclude.
3. **When a check fails, read the failing step, then classify.** Get only the
   failing log: `gh run view <run-id> --repo <owner/repo> --job <job-id>
   --log-failed`, or the full log through the runner's failure markers:
   R testthat `── Failure|── Error|\[ FAIL`; pytest `FAILED|ERROR`; jest `●`;
   cargo `test .* FAILED|panicked`. Put every failure in exactly one class:
   - **(a) Introduced by this change** — fix, run locally, push, re-watch.
   - **(b) Pre-existing on the base branch** — prove it: the base's latest
     runs (`gh run list --repo <owner/repo> --branch <base> --limit 5`) and
     that run's log show the same failure, or it reproduces on a local
     checkout of the base.
   - **(c) Infrastructure** — empty secrets on a fork PR, runner or cache
     outage, network flake, deprecation warning promoted to error. Quote the
     exact log line that proves it.
   Never call a failure "pre-existing" or "flaky" without that evidence.
4. **Report the PR together with its CI state.** Give the user:
   - a small table: check name, status, class (a/b/c) for each failure;
   - for each failure, the log line that proves its class;
   - what you changed and pushed in response;
   - what remains for the maintainer.
   If CI is red for reasons outside the PR's control, say so in one short
   paragraph in the PR description or a comment so maintainers see it, but
   edit the PR only when the user asked you to open or update it.
5. **Re-watch after every push.** Each push restarts rule 2. Keep the local
   run of the same tests green before pushing again.
6. **Useful incantations** (add `--repo <owner/repo>` outside the checkout):
   ```sh
   gh pr checks <num>                                   # one-shot state
   gh pr checks <num> --watch --interval 60             # block until concluded
   gh pr view <num> --json statusCheckRollup            # machine-readable state
   gh run list --branch <branch> --limit 5              # runs for a branch
   gh run view <run-id>                                 # jobs and their ids
   gh run view <run-id> --job <job-id> --log-failed     # failing steps only
   gh run view <run-id> --log | grep -nE '<markers>'    # search the full log
   gh run rerun --failed <run-id>                       # proven infra flakes only
   gh api repos/{owner}/{repo}/actions/runs/{id}/jobs   # job ids, steps, conclusions
   ```
   Re-run failed jobs only for a failure proven to be class (c), and tell the
   user you did.

Scope: this skill governs watching and interpreting CI. It does not authorise
opening PRs, pushing or force-pushing on its own; those still follow the
user's instructions and the repo's own AGENTS.md or CLAUDE.md.
