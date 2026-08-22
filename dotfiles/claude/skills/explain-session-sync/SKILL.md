---
name: explain-session-sync
description: Rebase an existing Markdown explanation tree onto the current Claude Code session, replacing its expired or outdated coordinator fork.
argument-hint: <path-to-explanation.md-or-root>
disable-model-invocation: true
allowed-tools:
  - Bash(explainctl *)
---

# Explain session sync

Call:

```sh
explainctl sync "$ARGUMENTS"
```

This forks the current session, points the fork at the existing explanation
tree, and records it as the tree's new coordinator. The documents are not
rewritten.

Do not explain anything in this session. Return only the tree path and the new
coordinator session ID from the command's JSON result.
