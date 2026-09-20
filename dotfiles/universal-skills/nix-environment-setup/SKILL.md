---
name: nix-environment-setup
description: Use when a command in a non-system project on this NixOS host fails because a tool, library, or environment variable is missing (command not found, R CMD check wanting pdflatex, a CLI not in nixpkgs), and the fix belongs in that project's own shell.nix and .envrc under direnv. Never use for /home/andongni/.nixos-config or any NixOS/Home Manager/system configuration repo — installs there are configuration changes, not dev shells — and not merely because a repo contains Nix files or a flake.nix.
---

# Nix Environment Setup

Tooling on this host is per project: each project directory carries a
`shell.nix` (`pkgs.mkShell`) and an `.envrc` containing `use nix`, loaded by
direnv. Nothing is installed globally.

## Workflow

1. Run the failing command from the project directory first; only act if it
   fails for a missing tool or variable.
2. Missing program: add the package to the existing `shell.nix`, preserving
   its entries. Missing variable: add it to `.envrc`, preserving other lines.
   Create either file only if absent; a new `.envrc` must contain `use nix`.
3. If `.envrc` was created or changed, run `direnv allow`. Confirm the
   addition with `nix-shell shell.nix --run '<cmd>'`: this session's
   environment predates the edit, so a bare run cannot show it.

Never reach for `nix-env -i`, `nix profile install`, `pip install --user`,
`/tmp` installs, or custom code standing in for a package that nixpkgs has.

## Host specifics

- CLIs not packaged cleanly in nixpkgs are wrapped declaratively inside
  `shell.nix` with `pkgs.writeShellApplication` + `uvx`; the reference
  example is `/home/andongni/Yandex.Disk/Projects/Research/modules/shell.nix`.
  Some `.envrc` files there export tokens: never copy those into another
  project.
- Interactive dev shells default to Bash (the login shell is zsh). A bare
  `exec bash` in `shellHook` breaks direnv's `use nix` and `nix-shell --run`,
  so guard it:

  ```nix
  shellHook = ''
    if [[ $- == *i* && -z "''${DIRENV_IN_ENVRC:-}" && "''${SHELL:-}" != */bash ]]; then
      exec bash
    fi
  '';
  ```
