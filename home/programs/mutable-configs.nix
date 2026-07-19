{ config, osConfig, ... }:

let
  # Hand-edited configs we want to (1) edit without a rebuild and (2) keep in
  # git and carried onto a fresh install. mkOutOfStoreSymlink points $HOME at
  # the working tree in the config repo (portable.configDir) instead of a
  # read-only /nix/store copy, so edits are live and land in version control.
  #
  # Only the authored subpaths below are linked. Secrets, session history, and
  # caches stay mutable and unmanaged in place (e.g. ~/.codex/auth.json,
  # ~/.config/claude/.credentials.json, projects/, sessions/, sqlite logs).
  #
  # Directory links are robust: files the app creates or rewrites inside them
  # land in the repo. Single-file links (AGENTS.md, config.toml, CLAUDE.md,
  # statusline.sh) can be replaced by a real file if the owning app rewrites
  # them via a temp-file+rename; if that happens, re-run `nixos-rebuild switch`
  # to restore the link. ~/.config/claude/settings.json is intentionally NOT
  # linked because the darkman theme switcher rewrites it via mktemp+mv on every
  # theme change, which would clobber the symlink.
  link = subpath: config.lib.file.mkOutOfStoreSymlink "${osConfig.portable.configDir}/${subpath}";
in
{
  home.file = {
    # Codex CLI (~/.codex) — authored config only.
    ".codex/AGENTS.md".source = link "dotfiles/codex/AGENTS.md";
    ".codex/config.toml".source = link "dotfiles/codex/config.toml";
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
  };
}
