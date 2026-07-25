# TODO: the documented pre-commit verification gate is not installed

Recorded 2026-07-25.

## Problem

`CLAUDE.md` names pre-commit hooks as this repo's only verification gate, in two
places:

- **Rebuild Policy:** "do not run standalone verification commands before
  rebuilding. Stage and commit the scoped change first so the configured
  pre-commit hooks run verification, then apply the committed configuration with
  `rebuild`."
- **Commit & Pull Request Guidelines:** "Treat the pre-commit hooks as the
  verification gate before `rebuild`."

No hook actually runs on commit. Verified on 2026-07-25 in the main checkout
`/home/andongni/.nixos-config`:

- `git config --get core.hooksPath` is unset (exit status 1).
- `.git/hooks/` contains only Git's inert `*.sample` templates.
- No `.pre-commit-config.yaml` exists anywhere in the repo (it is also
  `.gitignore`d, line 2, since it is generated rather than committed).

So every commit in this repo is currently unverified, and the policy actively
discourages the manual checks that would otherwise catch problems. As written it
is worse than no policy until the hooks exist.

## The flake is wired, the hook is not

`flake.nix` is not the missing piece — it already wires
`github:cachix/pre-commit-hooks.nix`:

- input `pre-commit-hooks` (line 15);
- `preCommitCheck = pre-commit-hooks.lib.${system}.run { ... }` (line 59);
- `checks.${system}.pre-commit` (line 74);
- `devShells.${system}.default` inherits `preCommitCheck.shellHook` and ships
  `nixfmt` and `pre-commit` (lines 78–84).

The gap is installation. That `shellHook` is what writes
`.pre-commit-config.yaml` and installs `.git/hooks/pre-commit`, and it only runs
on entering the dev shell. There is no `.envrc` and no direnv setup in the repo,
so `nix develop` is never entered in normal use and the hook is never installed.
Worktrees under `.claude/worktrees/` share the same uninstalled hook state via
the common git dir.

Two further gaps even once installed:

- The configured hook set is `nixfmt` plus `nix-gc`. `nix-gc` is garbage
  collection pinned to the `pre-push` stage — it is not verification. So the
  effective commit-time gate would be formatting only.
- Nothing checks shell scripts or flake evaluation.

## Interim workaround actually in use

For commit `41b1eed` "Suppress local startup terminal on remote role"
(2026-07-25), verification was done by hand:

- `shellcheck` on changed shell scripts;
- `nixfmt --check` on changed `.nix` files;
- `nix eval --impure` against the relevant
  `nixosConfigurations.system.config...` attribute, to confirm the flake still
  evaluates.

## Options (not decided)

For installation, either:

- add an `.envrc` (`use flake`) plus direnv so the `shellHook` installs the hook
  automatically, or
- run `nix develop` once to install it, or
- commit a plain `.pre-commit-config.yaml` and drop the generated-file
  `.gitignore` entry.

For coverage, a minimum useful hook set given this repo:

- `nixfmt` on `*.nix` (already configured);
- `shellcheck` on `dotfiles/**/*.sh` (23 files). Note the pre-existing
  `dotfiles/hypr/scripts/monitor-switch.sh:67` SC2034 (`i appears unused` in
  `for i in $(seq 1 6)`), which needs a fix or an inline disable before this
  hook can pass;
- a flake-evaluation check.

A full `nixos-rebuild build` as a hook would almost certainly be too slow to be
practical, so eval-only is the pragmatic choice.

## Open question for the user

Decide which way the mismatch is resolved: install and broaden the hooks so
`CLAUDE.md` becomes true, or amend `CLAUDE.md` to describe the manual
verification that is actually happening. Not decided here.
