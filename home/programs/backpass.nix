{
  lib,
  osConfig,
  pkgs,
  ...
}:

let
  peerHost = osConfig.portable.peerHost;

  # Same snapshot rule as claude.nix: interpolate the derivation, never
  # `toString path`, so the file stays reachable after garbage collection.
  claudeEnvironment = pkgs.writeText "claude-environment.json" (
    builtins.readFile ../../dotfiles/claude/environment.json
  );

  # acpx spawns the Claude adapter from whatever shell ran backpass, so the
  # bundled Claude Code inside it sees none of the launcher's environment.
  # Give it the standard profile's config dir and the proxy and privacy
  # defaults from environment.json, so it authenticates and routes exactly as
  # an interactive `claude` does.
  claudeAdapter = pkgs.writeShellApplication {
    name = "backpass-claude-agent-acp";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      export CLAUDE_CONFIG_DIR="''${CLAUDE_CONFIG_DIR:-$HOME/.config/claude}"

      claude_env_value() {
        jq -r --arg key "$1" '.[$key] // empty' ${lib.escapeShellArg "${claudeEnvironment}"}
      }
      export ALL_PROXY="''${ALL_PROXY:-$(claude_env_value ALL_PROXY)}"
      export DISABLE_ERROR_REPORTING="''${DISABLE_ERROR_REPORTING:-$(claude_env_value DISABLE_ERROR_REPORTING)}"
      export HTTPS_PROXY="''${HTTPS_PROXY:-$(claude_env_value HTTPS_PROXY)}"
      export HTTP_PROXY="''${HTTP_PROXY:-$(claude_env_value HTTP_PROXY)}"
      export NO_PROXY="''${NO_PROXY:-$(claude_env_value NO_PROXY)}"
      export http_proxy="$HTTP_PROXY"
      export https_proxy="$HTTPS_PROXY"
      export all_proxy="$ALL_PROXY"
      export no_proxy="$NO_PROXY"

      exec ${lib.getExe pkgs.claude-agent-acp} "$@"
    '';
  };

  # A config entry sharing a built-in name replaces that built-in, so `acpx
  # claude` (what backpass runs) uses the packaged adapter instead of
  # `npx -y @agentclientprotocol/claude-agent-acp`.
  acpxConfig = {
    agents.claude.argv = [ (lib.getExe claudeAdapter) ];
  };

  # Personal backpass configuration, layered under any repo's .backpassrc.json.
  #
  # Ladders: both passes pinned to Claude. The stock ladders try GPT via pi,
  # opencode or codex first, and each of those adapters is another `npx -y`
  # download at run time; only the Claude adapter is packaged here.
  #
  # Hosts: the peer joins the corpus over SSH. Nothing is installed there;
  # backpass pipes a one-shot program into the named Node, which is the same
  # store path on both hosts once both run this configuration. The remote
  # config dir has to be named because SSH never carries our session
  # variables across. This is the one setting a repo file may not carry.
  #
  # User scope trains ~/.config/claude/CLAUDE.md, a file only Claude Code
  # loads, so only Claude sessions are evidence for it; Codex and pi read
  # their own user files. Project scope is set per repo.
  backpassConfig = {
    ladders = {
      analysis = [
        {
          model = "claude-sonnet-5";
          agents = [ "claude" ];
        }
      ];
      synthesis = [
        {
          model = "claude-opus-5";
          agents = [ "claude" ];
        }
      ];
    };
    discovery.hosts = lib.optional (peerHost != "") {
      host = peerHost;
      node = lib.getExe pkgs.nodejs;
      env.CLAUDE_CONFIG_DIR = "~/.config/claude";
      harnesses = [
        "claude"
        "codex"
        "pi"
      ];
    };
    user.discovery.harnesses = [ "claude" ];
  };
in
{
  home.packages = [
    pkgs.backpass
    pkgs.acpx
  ];

  home.file.".acpx/config.json".text = builtins.toJSON acpxConfig;
  xdg.configFile."backpass/config.json".text = builtins.toJSON backpassConfig;
}
