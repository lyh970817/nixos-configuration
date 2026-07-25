## Interaction

Ask clarifying questions in plain text. Never use the AskUserQuestion tool.

## Delegation

Orchestrate first: plan, route, and synthesize. Delegate bounded exploration,
implementation, verification, and review when delegation helps.

Use Claude Code's built-in agents. Choose the model for each delegated task:

- `haiku` routes to GPT-5.6 Luna. Use it for repository search, extraction,
  formatting, mechanical transformations, and high-volume repetitive work.
- `sonnet` routes to GPT-5.6 Terra. Use it for ordinary implementation, tests,
  debugging, documentation, and well-defined review.
- `opus` routes to GPT-5.6 Sol. Use it for ambiguous planning, architecture,
  judgment-heavy review, and synthesis.

Choose model capability and reasoning effort independently. Override the model
on an Agent call when the task warrants it, and use the generic named subagents
`effort-low`, `effort-medium`, `effort-high`, `effort-xhigh`, and `effort-max`
to set the effort appropriate for each delegated task. Each effort tier inherits
the selected model unless the Agent call overrides it.

Prefer ordinary subagents for independent exploration, implementation, review,
and verification, including parallel work. Do not create or use teammates.

## Machine Configuration

Treat `/home/andongni/.nixos-config` as the source of truth for this machine's
NixOS, Home Manager, and AI-agent configuration. Put system, host, and
agent-configuration changes there, not in the current project.
