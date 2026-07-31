# Agent configuration files

Agent state belongs in this repository when it is needed to reproduce an agent's behavior on a new installation. How it is deployed depends on whether the agent mutates it at runtime.

## Include as a copied base or template

Include user-facing configuration files that the agent rewrites while it runs. Keep a representative base or template in `dotfiles/`, then copy it into place only when the runtime file does not exist. Declarative activation may reconcile settings that this repository intentionally owns, but the runtime file must remain writable and must not be an out-of-store symlink.

Examples include OMP `config.yml` files and Codex configuration that controls enabled or disabled skills. Runtime changes remain local instead of dirtying the configuration checkout.

## Include as an out-of-store symlink

Include static, user-authored resources that agents read but do not normally rewrite, and expose them with `mkOutOfStoreSymlink` so edits in this checkout take effect directly.

Examples include custom themes, user-authored skills, prompts, rules, and LSP definitions.

## Exclude

Do not include machine state, caches, logs, histories, sessions, databases and their journal files, generated indexes, marketplace caches, installed plugin payloads, lock state maintained by the agent, credentials, or other secrets. Generated or downloaded resources belong in the repository only when they become intentionally maintained source files rather than runtime state.

When a directory mixes these categories, declare individual static resources and templates instead of linking or copying the whole directory.
