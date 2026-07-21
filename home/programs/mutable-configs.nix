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

  claudeSettings = ../../dotfiles/claude/settings.json;
  claudeConfigDirs = [
    ".config/claude"
    ".config/claude-mattpocock"
  ];

  # Codex resolves profile-relative skill paths from the profile file's runtime
  # location. Materialize these tracked files at ~/.codex instead of linking
  # them to a store or worktree location, so the portable relative paths keep
  # the ~/.codex and ~/.agents roots on every host.
  codexProfiles = {
    "last30days.config.toml" = ../../dotfiles/codex/profiles/last30days.config.toml;
    "lavish-axi.config.toml" = ../../dotfiles/codex/profiles/lavish-axi.config.toml;
    "mattpocock.config.toml" = ../../dotfiles/codex/profiles/mattpocock.config.toml;
    "openai.config.toml" = ../../dotfiles/codex/profiles/openai.config.toml;
    "superpowers.config.toml" = ../../dotfiles/codex/profiles/superpowers.config.toml;
    "understand-anything-codegraph.config.toml" =
      ../../dotfiles/codex/profiles/understand-anything-codegraph.config.toml;
  };
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

    ${lib.concatMapStringsSep "\n" (configDir: ''
      claude_settings_dir="$HOME/${configDir}"
      claude_settings="$claude_settings_dir/settings.json"
      run ${pkgs.coreutils}/bin/install -d -m 0700 "$claude_settings_dir"
      claude_settings_tmp="$(${pkgs.coreutils}/bin/mktemp "$claude_settings.XXXXXX")"

      ${pkgs.jq}/bin/jq --arg theme "$claude_theme" \
        '.theme = $theme' \
        ${lib.escapeShellArg (toString claudeSettings)} > "$claude_settings_tmp"

      run ${pkgs.coreutils}/bin/chmod 0600 "$claude_settings_tmp"
      run ${pkgs.coreutils}/bin/mv -f "$claude_settings_tmp" "$claude_settings"
    '') claudeConfigDirs}
  '';

  home.activation.codexProfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: source: ''
        run ${pkgs.coreutils}/bin/install -D -m 0644 -- \
          ${lib.escapeShellArg (toString source)} \
          "$HOME/.codex/${name}"
      '') codexProfiles
    )}
  '';

  home.file = {
    # Codex CLI (~/.codex) — portable authored files only. The base
    # config.toml remains machine-local and unmanaged. Named profiles are
    # materialized by the activation above so their relative paths resolve
    # from ~/.codex.
    ".codex/AGENTS.md".source = link "dotfiles/codex/AGENTS.md";
    ".codex/rules".source = link "dotfiles/codex/rules";
    ".codex/skills".source = link "dotfiles/codex/skills";

    # Curated agent skill set + local plugins (~/.agents).
    ".agents".source = link "dotfiles/agents";
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
    "claude-mattpocock/skills/nix-environment-setup" = {
      source = link "dotfiles/claude/skills/nix-environment-setup";
      force = true;
    };
    "claude-mattpocock/skills/system-maintenance" = {
      source = link "dotfiles/claude/skills/system-maintenance";
      force = true;
    };
    "claude-mattpocock/skills/visual-verification" = {
      source = link "skills/visual-verification";
      force = true;
    };
  };
}
