{ pkgs, lib, config, ... }:

let
  settings = {
    env = {
      ANTHROPIC_AUTH_TOKEN = "test";
      ANTHROPIC_BASE_URL = "http://localhost:8080";
      _ANTHROPIC_MODEL = "gemini-3-pro-high[1m]";
      ANTHROPIC_DEFAULT_OPUS_MODEL = "gemini-3-pro-high[1m]";
      ANTHROPIC_DEFAULT_SONNET_MODEL = "gemini-3-flash[1m]";
      ANTHROPIC_DEFAULT_HAIKU_MODEL = "gemini-3-flash[1m]";
      CLAUDE_CODE_SUBAGENT_MODEL = "gemini-3-flash[1m]";
      ENABLE_EXPERIMENTAL_MCP_CLI = "true";
      DISABLE_TELEMETRY = "1";
      DISABLE_ERROR_REPORTING = "1";
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
      MCP_TIMEOUT = "60000";
    };
    includeCoAuthoredBy = false;
    permissions = {
      allow = [
        "Bash" "BashOutput" "Edit" "Glob" "Grep" "KillShell"
        "NotebookEdit" "Read" "SlashCommand" "Task" "TodoWrite"
        "WebFetch" "WebSearch" "Write" "mcp__ide" "mcp__exa"
        "mcp__context7" "mcp__mcp-deepwiki" "mcp__Playwright"
        "mcp__spec-workflow" "mcp__open-websearch" "mcp__serena"
      ];
      deny = [];
    };
    model = "opus";
  };

in {
  home.file.".claude/settings.json".text = builtins.toJSON settings;
  home.file.".claude/CLAUDE.md".text = "Always respond in English\n";

  # Note: Custom commands and agents in .claude/commands/zcf and .claude/agents/zcf
  # are currently left as manually managed or can be migrated to this file using recursive file linking
  # if we move the source files into the nixos repo.
}
