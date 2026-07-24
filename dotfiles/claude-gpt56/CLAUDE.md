## Tools

Never use the AskUserQuestion tool. Ask clarifying questions as plain text instead.

## Subagents

Act primarily as an orchestrator: plan, route, and synthesize. Delegate bounded
exploration, implementation, verification, and review when delegation helps.

Use Claude Code's built-in agents. This profile intentionally has no custom
role-agent presets in `agents/`; persistent agent definitions are not required
for the Agent tool or for subagent spawning.

Choose the semantic model slot for each Agent call according to the delegated
work:

- `haiku` routes to GPT-5.6 Luna for repository search, extraction, formatting,
  mechanical transformations, and high-volume repetitive work.
- `sonnet` routes to GPT-5.6 Terra for ordinary implementation, testing,
  debugging, documentation, and well-defined review.
- `opus` routes to GPT-5.6 Sol for ambiguous planning, architecture,
  judgment-heavy review, and synthesis.

The profile's `modelOverrides` map the Claude Code 2.1.217 canonical model
behind each native semantic slot to the gateway:

- `opus` (`claude-opus-4-8`) -> `claude-gpt-5-6-sol`
- `sonnet` (`claude-sonnet-5`) -> `claude-gpt-5-6-terra`
- `haiku` (`claude-haiku-4-5-20251001`) -> `claude-gpt-5-6-luna`

These canonical Claude IDs are version-specific. After upgrading Claude Code,
verify all three semantic slots and built-in Agent routing against live
`modelUsage`; update `modelOverrides` if Claude changes the canonical IDs.

Built-in subagents inherit the session's native effort setting. The Agent tool
can select a model for a call, but it does not expose a per-call effort
argument. Select `low`, `medium`, `high`, `xhigh`, or `max` for the session
through Claude Code's native effort control; CLIProxyAPI translates it to the
upstream reasoning effort.

Do not set or rely on `CLAUDE_CODE_SUBAGENT_MODEL`; the launcher deliberately
unsets that global pin. Gateway model discovery is also disabled so this
profile exposes only the three semantic GPT-backed slots rather than raw or
cloud model entries.

## Machine Configuration

`/home/andongni/.nixos-config` is the source of truth for this machine's NixOS,
Home Manager, and AI-agent configuration. System, host, and agent-config changes
and installs belong there, not the current project.

The GPT-5.6 Claude Code profile is isolated under
`~/.config/claude-gpt56`. Its local gateway is CLIProxyAPI at
`http://127.0.0.1:8317`. Use `cli-proxy-api-codex-login` for the one-time Codex
OAuth login and `claude-gpt56` (or `clg`) to launch the profile.
