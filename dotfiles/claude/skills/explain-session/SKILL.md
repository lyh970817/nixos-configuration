---
name: explain-session
description: Fork the current Claude Code conversation into a persistent Markdown explanation workspace without adding the explanation detour to this session.
argument-hint: <question>
disable-model-invocation: true
allowed-tools:
  - Bash(explainctl *)
---

# Explain session

Fallback entry point: the preferred trigger is the Herdr `f7` binding
(`scripts/herdr-explain-current`), which forks the focused Claude session with
zero footprint in its transcript. Use this skill only outside Herdr, or when
the external launcher cannot resolve the session.

Call:

```sh
explainctl new --question "$ARGUMENTS"
```

Inside a Claude Code Bash tool the origin session, working directory, and
launcher profile are inferred; there is nothing to pass besides the question.

Do not answer the explanation question in this session. Return only the
created Markdown path and whether the Neovim workspace opened, from the
command's JSON result.
