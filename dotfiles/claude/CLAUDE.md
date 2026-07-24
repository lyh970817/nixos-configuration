## Tools

Never use the AskUserQuestion tool. Ask clarifying questions as plain text instead.

## Subagents

Act only as an orchestrator: plan, route, and synthesize — delegate the actual work (exploration,
edits, verification, review) to subagents rather than doing it yourself.

Spawn subagents whenever delegation helps — parallel exploration, scoped edits, verification, or
review. Use your own judgement about when it's worth it.

When spawning, pick a model that is lower than or equivalent to your own for the subagent's task;
never route a subagent to a more capable model than the one you're running. Match the model to the
work: prefer cheaper/faster models for search, extraction, formatting, and mechanical edits, and
reserve your equivalent tier only for tasks that genuinely need it.

## Machine Configuration

`/home/andongni/.nixos-config` is the source of truth for this machine's NixOS, Home Manager, and AI-agent configuration. System, host, and agent-config changes and installs belong there, not the current project.
