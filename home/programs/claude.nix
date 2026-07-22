{
  pkgs,
  lib,
  osConfig,
  ...
}:

let
  claudeHostLauncher = pkgs.writeShellApplication {
    name = "claude";
    text = ''
      export CLAUDE_CONFIG_DIR="''${CLAUDE_CONFIG_DIR:-$HOME/.config/claude}"

      export TZ="Europe/London"
      export TZDIR="${pkgs.tzdata}/share/zoneinfo"

      export LANG="en_GB.UTF-8"
      export LC_ALL="en_GB.UTF-8"
      export LANGUAGE="en_GB:en"
      export LOCALE_ARCHIVE="${pkgs.glibcLocales}/lib/locale/locale-archive"

      export HTTP_PROXY="''${HTTP_PROXY:-http://127.0.0.1:7890}"
      export HTTPS_PROXY="''${HTTPS_PROXY:-http://127.0.0.1:7890}"
      export ALL_PROXY="''${ALL_PROXY:-socks5h://127.0.0.1:7890}"
      export NO_PROXY="''${NO_PROXY:-localhost,127.0.0.1,::1,.local,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12}"

      export http_proxy="$HTTP_PROXY"
      export https_proxy="$HTTPS_PROXY"
      export all_proxy="$ALL_PROXY"
      export no_proxy="$NO_PROXY"

      export DISABLE_TELEMETRY="1"
      export DISABLE_ERROR_REPORTING="1"
      export ENABLE_EXPERIMENTAL_MCP_CLI="true"
      export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="1"
      # Force full alt-screen repaints to stop residual flicker/jumping on the
      # fullscreen renderer (terminal coalesces positioned writes otherwise).
      export CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT="1"
      # Classic renderer has no keyboard transcript scrolling; force the fullscreen one.
      export CLAUDE_CODE_NO_FLICKER="1"
      export MCP_TIMEOUT="60000"

      exec ${pkgs.claude-code}/bin/claude "$@"
    '';
  };

in
{
  # Coding CLI: installed on both home and remote roles.
  config = {
    home.packages = [
      claudeHostLauncher
    ];

    home.sessionVariables.CLAUDE_CONFIG_DIR = "$HOME/.config/claude";

    # Commands, agents, and runtime profile state stay mutable under
    # CLAUDE_CONFIG_DIR. settings.json is materialized from the tracked
    # non-secret baseline, then the theme hooks keep each profile's theme live.
  };
}
