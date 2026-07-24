## Tools

Never use the AskUserQuestion tool. Ask clarifying questions as plain text instead.

## Subagents

Act primarily as an orchestrator: plan, route, and synthesize. Delegate bounded
exploration, implementation, verification, and review when delegation helps.

For every Agent call, choose the model and effort independently to fit that
specific delegation. Do not inherit one fixed subagent model merely because it
is the main-session model. The custom agents in `agents/` provide useful
defaults, but you may override their model and effort on each Agent call.

Use this routing policy:

- Luna low or medium: repository search, extraction, formatting, mechanical
  transformations, and high-volume repetitive work.
- Terra medium or high: ordinary implementation, testing, debugging,
  documentation, and well-defined review.
- Terra xhigh or max: difficult but well-scoped implementation and debugging.
- Sol medium or high: ambiguous planning, architecture, judgment-heavy review,
  and synthesis.
- Sol xhigh or max: only the hardest judgment-heavy tasks where the additional
  reasoning depth is materially useful.

The gateway exposes one base alias for each GPT-5.6 model:

- `claude-gpt-5-6-sol`
- `claude-gpt-5-6-terra`
- `claude-gpt-5-6-luna`

Select `low`, `medium`, `high`, `xhigh`, or `max` separately through Claude
Code's native effort setting. CLIProxyAPI translates that setting to the
upstream `reasoning.effort`; no model alias fixes or overrides the effort.
Never set or rely on `CLAUDE_CODE_SUBAGENT_MODEL`; the launcher deliberately
unsets that global pin so each delegation remains independently routable.

When spawning, never route a subagent to a model more capable than the current
orchestrator. Prefer the least expensive model and lowest effort that still fit
the work.

## Machine Configuration

`/home/andongni/.nixos-config` is the source of truth for this machine's NixOS,
Home Manager, and AI-agent configuration. System, host, and agent-config changes
and installs belong there, not the current project.

The GPT-5.6 Claude Code profile is isolated under
`~/.config/claude-gpt56`. Its local gateway is CLIProxyAPI at
`http://127.0.0.1:8317`. Use `cli-proxy-api-codex-login` for the one-time Codex
OAuth login and `claude-gpt56` (or `clg`) to launch the profile.
