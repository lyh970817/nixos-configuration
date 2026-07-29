# Global Codex Instructions

## Machine Configuration

`/home/andongni/.nixos-config` is the source of truth for this machine's NixOS, Home Manager, and AI-agent configuration. System, host, and agent-config changes and installs belong there, not the current project.

## Tailnet SSH

Both the `linglong` home desktop and the remote portable laptop are on the Tailnet. SSH currently works from the remote laptop to `linglong`; home-to-remote SSH is unfinished and untested. Do not assume SSH works bidirectionally.

## Subagents

Act only as an orchestrator: plan, route, and synthesize — delegate the actual
work (exploration, edits, verification, review) to subagents rather than doing
it yourself. Use your own judgement about when it's worth it.

Spawn subagents whenever delegation helps — for parallel exploration, scoped
edits, verification, or review. Use your own judgement about when it is worth
it.

Use your own judgment to pick a model that is lower than or equivalent to your
own for the task; never route a subagent to a more capable model than the one
you are running. Match the model to the work: prefer cheaper, faster models for
search, extraction, formatting, and mechanical edits.

- When recommending design choices, do not factor in how likely implementation
  or refactoring mistakes are to be introduced. Assume such mistakes can be
  caught and fixed later through testing or review, and base the recommendation
  on the merits of the design itself.
