# Repository Guidelines

## Project Structure & Module Organization

One generic NixOS flake serving two machines: the `linglong` home desktop and a
remote portable laptop, split by `portable.role` (`"home"` / `"remote"`). Enter
at `flake.nix` for the system and `home/andongni.nix` for Home Manager; both
trees are organized by feature underneath. Per-machine facts (hardware,
hostname, `portable.role`/`peerHost`/`configDir`) come from gitignored
`/etc/nixos/hardware-configuration.nix` and `/etc/nixos/local.nix`, imported by
absolute path — hence `--impure`. Modules gated on
`osConfig.portable.role == "home"` give the remote laptop a lighter set.

## Build, Test, and Development Commands

- `rebuild`: apply the configuration to the local host, from any directory
  (`/etc/nixos` is a symlink to this checkout).
- `sudo nixos-rebuild switch --flake .#system --impure`: apply directly when
  already in this checkout.

## Rebuild Policy

For configuration changes, do not run standalone verification commands before
committing; stage and commit the scoped change. `rebuild` is the verification
gate. The pre-commit hooks (`flake.nix`, `home/programs/pre-commit.nix`) cover
only what a rebuild structurally cannot see, so a clean commit does not mean the
configuration evaluates.

A configuration change is complete only after its committed history is
synchronized to both role checkouts and both hosts rebuild successfully. Use
the `work-on-peer-device` skill for role discovery, safe Git transfer, and the
peer procedure.

For visual changes, perform visual verification automatically. The mode active
at task start is the entire change scope; change or inspect the other mode only
when the user asks. Before committing, a visual preview may use reliably
reversible runtime overrides or isolated temporary configs, but must not run an
uncommitted Home Manager activation or NixOS rebuild. Commit the selected
result, and inspect the installed result through `screen-verify` once it has
been rebuilt.

## Mihomo Configuration: Safe Apply / Auto-Revert

Editing `secrets/mihomo-config.yaml` does nothing until mihomo restarts, and
`rebuild` does not restart it. Your own model connection runs through mihomo, so
apply an edit only through `mihomo-guard` (`modules/services/mihomo.nix`):

- `sudo mihomo-guard try` — arms a 90-second auto-revert, then restarts mihomo
  so the edit goes live. The TUN restart briefly interrupts **all** traffic.
- `sudo mihomo-guard keep` — you can still reach your model: confirm the edit and
  record it as the new baseline.
- `sudo mihomo-guard revert` — the edit is bad but you are still connected: undo
  it now.
- Connection dead: do nothing, you cannot. Within 90 seconds the timer restores
  the last-good config and restarts mihomo, and your connection comes back.

A reverted or auto-reverted edit is preserved at
`/var/lib/mihomo-config/rejected.yaml` for inspection afterwards.

## Store Garbage Collection: `-d` and Unknown Roots

`sudo nix-collect-garbage -d` deletes old generations in **every** profile and
supersedes a preceding `--delete-generations`; one invocation left a single
system generation and destroyed every boot-menu rollback target.

That is all `-d` adds. The other hazard is independent of it: a GC root does not
tell you what it is holding. Before deleting a stale `result*` symlink or
`.direnv` profile, check its closure (`nix-store -q --references`, `nix-store
--gc --print-live`). A leftover `result-iso` was the last root on the nixpkgs
source `~/.config/nix/registry.json` pinned `flake:nixpkgs` to; unpinning it let
the next plain `nix-collect-garbage` take it, and `<nixpkgs>` failed with `path
'//nix/store/…-source' does not exist` — the `//` marks registry resolution. A
`path:` pin has nothing to re-fetch from, so the loss is unrecoverable; prefer
`github:owner/repo/rev`, rooted under `/nix/var/nix/gcroots/per-user/<user>/`.

Reclaim space in this order:

1. Unpin stale GC roots — leftover `result*` symlinks, abandoned `.direnv`
   profiles — each checked first; deleting the symlink does not delete the store
   path. The store is large because paths are pinned, not because garbage
   accumulated (65G store, 2.6 GiB collectable, ~21 GiB pinned by user roots).
2. `sudo nix-env --delete-generations +10 --profile /nix/var/nix/profiles/system`,
   then `sudo /run/current-system/bin/switch-to-configuration boot`.
3. `sudo nix-collect-garbage` — no `-d`.
4. `sudo nix store optimise`, last, on the reduced store.

Scheduled upkeep (`modules/system/nix.nix`, `modules/system/boot.nix`) uses
`--delete-older-than` and touches neither hazard; both are manual.

Check generations under `sudo`: without it `nix-env --list-generations` exits 0
with empty output and `ls /boot/loader/entries` looks empty, both reading as
"nothing there".

## Updating the Pinned Agent Tools

`pkgs/claude-code.nix`, `pkgs/codex.nix` and `pkgs/chatgpt.nix` pin a version and
a hash. Moving the pin is not the whole task: report what changed between the old
and the new version.

Lead with behaviour changes — changed defaults, removed or renamed flags, altered
permission, hook or config semantics. Those break workflows already in use and
outrank new features. Then the added and changed features, marking the ones that
touch how the agents here are actually driven: multi-agent orchestration in
worktrees and background agents, skills (repo-local ones live in
`.agents/skills/`), hooks and `settings.json` permissions, MCP servers,
file-based memory, context handling in long sessions, driving the peer host over
SSH, and anything that widens what an agent may do unasked or undoably.

Where the notes live:

- Claude Code —
  `https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md`.
- Codex CLI — the GitHub release for tag `rust-v<version>`
  (`https://api.github.com/repos/openai/codex/releases/tags/rust-v<version>`),
  whose body is categorized by hand. The repo's `CHANGELOG.md` is a stub that
  only points there, and most tags are prereleases with an empty body, so filter
  on `prerelease == false`.
- ChatGPT/Codex desktop — none. No public per-version changelog exists, the
  release-notes pages refuse automated fetches, and its `src` tracks a `latest`
  URL rather than a version. Report that the build moved and stop; do not hunt.

## Coding Style & Naming Conventions

Keep modules focused on one concern and name files by feature, for example
`modules/services/keyd.nix` or `home/programs/tmux.nix`. Prefer explicit imports
in aggregator files over hidden dynamic loading. Keep comments brief around
hardware, network, or host-specific behavior.

## Commit & Integration

Short imperative subjects, as in `Add 115 Browser launcher` or `Fix tmux
copy-mode paging keys`; no unrelated changes in one commit.

Committing your own work on your own branch or worktree needs no approval. Never
open pull requests. Merging into `master`, running `rebuild`, and pushing belong
to the top-level session: if another session gave you an implementation task,
never merge your own work into `master` and never push — leave it committed on
your branch and report it. A session that was explicitly delegated the merge
itself is the top-level session acting through you, and should merge, rebuild
and push as below. In the top-level session, merge, rebuild both hosts, and push
`master` to `origin` in the same turn you finish the change — that is delivering
it, not a separate thing to ask about. Pushing `master` to `origin` after a
merge is the only push that needs no asking; for anything else wait until the
user asks, and then push exactly what they named and nothing more. Every push
is fast-forward only, never `--force` or `--force-with-lease`, never
`--all`/`--tags`/`--mirror`, and never publishes feature or worktree branches
alongside the named branch. Do not park finished work on a branch for review
and do not offer a review step the user did not ask for; if they want to see it
first they will say so.

Cleanup is the last step of merging, and the condition is that the branch is
fully merged — `git branch --merged master`, or `git cherry master <branch>` when
it was rebased or squashed — not that the agent finished. Then `git worktree
remove` the checkout and `git branch -d` the branch.

## Security & Configuration Tips

Do not commit secrets, private SSH material, generated result symlinks, or
machine-local credentials. Keep sensitive settings manual unless already
represented safely in the flake. Be careful with `hardware-configuration.nix`,
network modules, boot settings, and service definitions because they affect
bootability or connectivity.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
