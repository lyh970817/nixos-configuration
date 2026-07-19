---
name: nix-environment-setup
description: Use when working on NixOS and environment setup is needed in the current project, including adding missing programs via `shell.nix` or adding/updating environment variables in `.envrc`. Enforce project-local setup with `shell.nix` and `.envrc`, run `direnv allow` only when `.envrc` is created, and only prompt the user to re-enter the directory when `.envrc` was changed or `direnv allow` was run.
---

# Nix Environment Setup

## Overview

Standardize project-local environment setup on NixOS with reproducible `shell.nix` and `.envrc` files.
Handle both dependency installation (through `shell.nix`) and environment variable configuration (through `.envrc`).

## Required Policy

Follow these rules whenever environment setup is needed:

1. For missing tools, create or update `shell.nix` in the current working directory.
2. For environment variables, create or update `.envrc` in the current working directory.
3. Ensure `.envrc` contains `use nix`.
4. Run `direnv allow` only if `.envrc` was created.
5. Prompt the user to leave and re-enter the directory only if `.envrc` changed or `direnv allow` was run.

Do not use imperative installation commands such as `nix-env -i`, `nix profile install`, `apt`, or `brew` for this workflow.

## Workflow

1. Identify whether the task requires:
   - adding program dependencies, or
   - adding/updating environment variables, or
   - both.
2. If dependencies are needed:
   - update existing `shell.nix` with only required packages, preserving existing entries; or
   - create `shell.nix` with `pkgs.mkShell` if missing.
3. If environment variables are needed:
   - update existing `.envrc` and preserve unrelated valid lines; or
   - create `.envrc` if missing.
4. Ensure `.envrc` includes `use nix`.
5. Track whether `.envrc` was created and whether its content changed.
6. Run `direnv allow` only when `.envrc` was newly created.
7. Prompt the user to re-enter the directory (for example `cd .. && cd -`) only when `.envrc` changed or after `direnv allow` is run.

## `shell.nix` Baseline Template

Use this template when creating a new file:

```nix
{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  packages = with pkgs; [
    # add required packages here
  ];
}
```

Prefer editing existing `shell.nix` instead of replacing it.

## Completion Checklist

Before declaring setup complete, verify:

- If dependency installation was requested, `shell.nix` exists in the current directory and contains all required packages.
- If environment variable setup was requested, `.envrc` exists in the current directory and contains expected variables.
- `.envrc` contains `use nix`.
- If `.envrc` was created, `direnv allow` was executed successfully.
- The user was prompted to re-enter the directory only when `.envrc` changed or `direnv allow` was run.
