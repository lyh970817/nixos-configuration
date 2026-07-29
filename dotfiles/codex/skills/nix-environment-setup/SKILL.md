---
name: nix-environment-setup
description: Use for non-system project work on NixOS only when a missing development tool/env var should be fixed with a project-local shell.nix, .envrc, and direnv setup. Do not use for /home/andongni/.nixos-config, NixOS/Home Manager/system configuration repos, or merely because a repo contains Nix files or flake.nix.
---

# Nix Environment Setup

## Entry Rule

When project tooling is missing on NixOS, enter this workflow before editing code, retrying the blocked task, or installing anything outside the project.

## Hard Stop

Environment setup must happen only in `codex --yolo`, where filesystem and network access are unrestricted.

If setup is needed while sandboxed, stop before creating or modifying `shell.nix`, creating or modifying `.envrc`, installing dependencies, running `direnv allow`, or validating downloaded Nix dependencies.

When stopping, tell the user exactly:

"This needs environment setup, which the skill requires in `codex --yolo`. Please restart/switch Codex with unrestricted access, then ask me to continue."

## Workflow

1. Run the intended project command directly from the project directory.
2. If it works, continue the original task and do not invoke `nix-shell`.
3. If it fails because a tool or variable is missing, confirm `codex --yolo` before setup.
4. Classify the missing setup:
   - Program dependency: add the required package or wrapper to `shell.nix`.
   - Environment variable: add the variable setup to `.envrc`.
   - Both: update both files.
5. Prefer existing programs over custom replacement code. If a packaged program solves the gap, add it to `shell.nix`.
6. Edit the project-local files:
   - Preserve existing `shell.nix` entries; create `shell.nix` with `pkgs.mkShell` if missing.
   - Every managed `shell.nix` must include `pkgs.bash` and a `shellHook` that runs `exec bash`, so entering the development shell always uses Bash rather than the invoking shell.
   - Preserve unrelated valid `.envrc` lines; create `.envrc` if missing.
   - Ensure `.envrc` contains `use nix` whenever `shell.nix` exists.
7. Reuse only safe patterns from example `shell.nix` or `.envrc` files. Never copy secrets or machine-specific values.
8. Track whether `.envrc` was created or changed.
9. Run `direnv allow` only if `.envrc` was created or changed.
10. If `direnv allow` ran, tell the user to reload the directory with `cd .. && cd -` or restart Codex.

Completion criterion: setup is complete only when the required project-local file changes are present, `.envrc` contains `use nix`, and `direnv allow` has succeeded if `.envrc` changed.

Do not require immediate post-setup verification. The current Codex process may not see the updated direnv environment until the directory is reloaded or Codex restarts.

## `shell.nix` Baseline Template

Use this template when creating a new file:

```nix
{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  packages = with pkgs; [
    bash
    # add required packages here
  ];
  shellHook = ''
    exec bash
  '';
}
```

Prefer editing existing `shell.nix` instead of replacing it.

If the project needs pinned CLIs that are not packaged cleanly in nixpkgs, prefer reproducible wrappers inside `shell.nix` over imperative installs. For example, a wrapped Python CLI can be exposed with `pkgs.writeShellApplication` and `uvx`, while still keeping the setup project-local and declarative.

## Forbidden Workarounds

Do not use these to get past missing project tooling:

- `nix-shell --run` after `.envrc` contains `use nix`, except when in `codex --yolo` and validating changes to the Nix shell environment itself. Keep that exception limited to small environment checks; do not use it to run ordinary project test/build workflows.
- `nix-env -i`, `nix profile install`, `apt`, `brew`, or global installs
- Temporary virtualenvs, `/tmp` installs, `pip install --user`, or one-off wrapper scripts outside the project
- Writing custom code to replace a program that could be added to `shell.nix`
- Editing code or retrying commands before fixing the missing environment dependency

Once `.envrc` contains `use nix`, run project commands directly from the project directory. If direct execution fails because direnv is not loaded, stop and tell the user to load or allow direnv.
