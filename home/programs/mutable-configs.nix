{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:

let
  # Hand-edited configs we want to (1) edit without a rebuild and (2) keep in
  # git and carried onto a fresh install. mkOutOfStoreSymlink points $HOME at
  # the working tree in the config repo (portable.configDir) instead of a
  # read-only /nix/store copy, so edits are live and land in version control.
  #
  # Only the authored subpaths below are linked. Machine-local base config,
  # secrets, session history, and caches stay mutable and unmanaged in place
  # (e.g. ~/.codex/config.toml, ~/.codex/auth.json,
  # ~/.config/claude/.credentials.json, projects/, sessions/, sqlite logs).
  #
  # Directory links are robust: files the app creates or rewrites inside them
  # land in the repo. Single-file links (AGENTS.md, CLAUDE.md, statusline.sh)
  # can be replaced by a real file if the owning app rewrites
  # them via a temp-file+rename; if that happens, re-run `nixos-rebuild switch`
  # to restore the link. Claude settings are materialized below instead: the
  # theme hook atomically replaces each profile's runtime JSON on every switch.
  link = subpath: config.lib.file.mkOutOfStoreSymlink "${osConfig.portable.configDir}/${subpath}";

  claudeProfiles = [
    {
      configDir = ".config/claude";
      settings = ../../dotfiles/claude/settings.json;
    }
    {
      configDir = ".config/claude-mattpocock";
      settings = ../../dotfiles/claude-mattpocock/settings.json;
    }
    {
      configDir = ".config/claude-gpt56";
      settings = ../../dotfiles/claude-gpt56/settings.json;
    }
  ];

  # Codex canonicalizes skill paths at scan time, so a symlinked profile
  # behaves identically to a materialized copy (verified with
  # `codex debug prompt-input`). Link profiles like everything else: edits are
  # live without a rebuild and Home Manager removes dropped ones on switch.
  # Force because pre-symlink generations left plain-file copies behind.
  codexProfileNames = [
    "last30days"
    "lavish-axi"
    "mattpocock"
    "superpowers"
    "understand-anything-codegraph"
  ];
  codexProfileLinks = lib.listToAttrs (
    map (name: {
      name = ".codex/${name}.config.toml";
      value = {
        source = link "dotfiles/codex/profiles/${name}.config.toml";
        force = true;
      };
    }) codexProfileNames
  );
in
{
  # Keep a tracked, non-secret Claude baseline while leaving each profile's
  # runtime file as an ordinary mutable file. Every activation replaces the
  # shared settings with that baseline and derives only its theme from the
  # active desktop mode. The files must be ordinary files because the theme
  # hooks replace them atomically.
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    claude_theme="dark-ansi"
    case "$(readlink "$HOME/.local/state/hypr/current-theme.conf" 2>/dev/null || true)" in
      *light.conf) claude_theme="light-ansi" ;;
    esac

    ${lib.concatMapStringsSep "\n" (profile: ''
      claude_settings_dir="$HOME/${profile.configDir}"
      claude_settings="$claude_settings_dir/settings.json"
      run ${pkgs.coreutils}/bin/install -d -m 0700 "$claude_settings_dir"
      claude_settings_tmp="$(${pkgs.coreutils}/bin/mktemp "$claude_settings.XXXXXX")"

      ${pkgs.jq}/bin/jq --arg theme "$claude_theme" \
        '.theme = $theme' \
        ${lib.escapeShellArg (toString profile.settings)} > "$claude_settings_tmp"

      run ${pkgs.coreutils}/bin/chmod 0600 "$claude_settings_tmp"
      run ${pkgs.coreutils}/bin/mv -f "$claude_settings_tmp" "$claude_settings"
    '') claudeProfiles}
  '';

  home.file = codexProfileLinks // {
    # Codex CLI (~/.codex) — portable authored files only. The base
    # config.toml remains machine-local and unmanaged (it holds absolute
    # project trust paths and Codex rewrites it at runtime).
    ".codex/AGENTS.md".source = link "dotfiles/codex/AGENTS.md";
    ".codex/rules".source = link "dotfiles/codex/rules";
    ".codex/skills".source = link "dotfiles/codex/skills";

    # Curated agent skill pool, shared with Codex profiles via relative
    # shared-skills/<name> paths. Force because a manually created bridge
    # symlink will already exist at activation time.
    ".codex/shared-skills" = {
      source = link "dotfiles/agents/skills";
      force = true;
    };
  };

  xdg.configFile = {
    # fcitx5 — global config, input-method profile, and per-addon conf/.
    # conf/cached_layouts regenerates here and is git-ignored; the learned
    # pinyin dictionary lives under ~/.local/share/fcitx5 and is untouched.
    "fcitx5".source = link "dotfiles/fcitx5";

    # Claude Code (CLAUDE_CONFIG_DIR=~/.config/claude) — stable authored config.
    "claude/CLAUDE.md".source = link "dotfiles/claude/CLAUDE.md";
    "claude/statusline.sh".source = link "dotfiles/claude/statusline.sh";
    "claude/skills".source = link "dotfiles/claude/skills";
    "claude/commands".source = link "dotfiles/claude/commands";
    "claude/output-styles".source = link "dotfiles/claude/output-styles";
    "claude/agents".source = link "dotfiles/claude/agents";

    # GPT-5.6 gateway profile. Share portable authored assets from the standard
    # profile, but keep credentials, history, sessions, plugins, caches, and all
    # other mutable state isolated under its own CLAUDE_CONFIG_DIR.
    "claude-gpt56/CLAUDE.md".source = link "dotfiles/claude-gpt56/CLAUDE.md";
    "claude-gpt56/statusline.sh".source = link "dotfiles/claude/statusline.sh";
    "claude-gpt56/commands".source = link "dotfiles/claude/commands";
    "claude-gpt56/output-styles".source = link "dotfiles/claude/output-styles";
    "claude-gpt56/agents".source = link "dotfiles/claude/agents";
    "claude-gpt56/skills/bro".source = link "dotfiles/claude/skills/bro";
    "claude-gpt56/skills/agent-config-setup".source = link "dotfiles/claude/skills/agent-config-setup";
    "claude-gpt56/skills/nix-environment-setup".source =
      link "dotfiles/claude/skills/nix-environment-setup";
    "claude-gpt56/skills/visual-verification".source =
      link "dotfiles/claude/skills/visual-verification";

    # Claude has a profile per CLAUDE_CONFIG_DIR. Share only portable authored
    # assets with claude-mattpocock; its credential, settings, plugin state,
    # history, and independently managed Matt Pocock skill set stay mutable.
    "claude-mattpocock/CLAUDE.md" = {
      source = link "dotfiles/claude/CLAUDE.md";
      force = true;
    };
    "claude-mattpocock/statusline.sh" = {
      source = link "dotfiles/claude/statusline.sh";
      force = true;
    };
    "claude-mattpocock/commands" = {
      source = link "dotfiles/claude/commands";
      force = true;
    };
    "claude-mattpocock/output-styles" = {
      source = link "dotfiles/claude/output-styles";
      force = true;
    };
    "claude-mattpocock/agents" = {
      source = link "dotfiles/claude/agents";
      force = true;
    };
    "claude-mattpocock/skills/nix-environment-setup" = {
      source = link "dotfiles/claude/skills/nix-environment-setup";
      force = true;
    };
    "claude-mattpocock/skills/agent-config-setup" = {
      source = link "dotfiles/claude/skills/agent-config-setup";
      force = true;
    };
    "claude-mattpocock/skills/visual-verification" = {
      source = link "skills/visual-verification";
      force = true;
    };
    "claude-mattpocock/skills/bro" = {
      source = link "dotfiles/claude/skills/bro";
      force = true;
    };
  };
}
