# Zsh Shell Configuration
# Managed by home-manager
{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:

let
  # Peer machine to hand our theme off to over SSH, baked from the host
  # config. Empty string ("" default) disables the client-side ssh wrapper.
  peerHost = osConfig.portable.peerHost;
in
{
  programs.zsh = {
    enable = true;
    dotDir = config.home.homeDirectory;

    # NO_APPEND_HISTORY (default) makes every cleanly-exiting shell rewrite
    # the whole history file instead of appending, and NO_EXTENDED_HISTORY
    # (default) drops timestamps. Pin the good behaviour explicitly so it
    # doesn't depend on Home Manager defaults, which can change silently on
    # a flake bump. ignoreSpace is deliberately left unset (its default,
    # true, already matches the live HIST_IGNORE_SPACE behaviour).
    history = {
      append = true;
      extended = true;
      share = true;
      size = 200000;
      save = 200000;
    };

    initContent = ''
      unsetopt BEEP
      KEYTIMEOUT=1
      export LS_COLORS="''${LS_COLORS}:ln=01;36:or=01;31:"

      # Silence zoxide's one-time doctor nag. It only checks that __zoxide_hook
      # is present in chpwd_functions (not that it is "last"), and fires
      # spuriously in non-interactive login shells such as Claude Code's bash
      # tool, where the hook ends up unregistered. Interactive shells register
      # it fine below, so this just suppresses the false positive. Set early so
      # it applies even if the rest of this file is cut short in those shells.
      export _ZO_DOCTOR=0

      # Persist directory stack across sessions
      DIRSTACKFILE="''${XDG_CACHE_HOME:-$HOME/.cache}/zsh/dirs"
      DIRSTACKSIZE=20
      [[ -d "''${DIRSTACKFILE:h}" ]] || mkdir -p "''${DIRSTACKFILE:h}"
      [[ -f "$DIRSTACKFILE" ]] && dirstack=("''${(@f)"$(< "$DIRSTACKFILE")"}")
      chpwd_dirstack() {
        print -l -- "$PWD" "''${(u)dirstack[@]}" > "$DIRSTACKFILE"
      }
      autoload -Uz add-zsh-hook
      add-zsh-hook -Uz chpwd chpwd_dirstack

      # THEME_MODE is the per-session colour layer (dark|light), independent
      # of this machine's own desktop appearance. Remote sessions get it from
      # theme-hold (see theming.nix), which exports it once at launch and
      # freezes it for that process's life. Locally — no incoming remote
      # session — it's unset here, so default it from this machine's own
      # monitor via theme-mode; anything other than dark/light (including
      # theme-mode failing) collapses to dark. Done once at startup, not in
      # the precmd hook below, since the mode never changes within a process.
      if [ -z "$THEME_MODE" ]; then
        THEME_MODE="$(theme-mode 2>/dev/null)"
      fi
      case "$THEME_MODE" in
      dark | light) ;;
      *) THEME_MODE="dark" ;;
      esac
      export THEME_MODE

      # Function to read the per-mode theme files and export variables.
      # Forkless zsh: $(<file) slurps the file without an external `cat`,
      # (f) splits it into lines, (j: :) rejoins them with spaces — no `tr`,
      # no subshell fork.
      load_shell_themes() {
        local fzf_file="$HOME/.config/fzf/themes/$THEME_MODE"
        local newt_file="$HOME/.config/newt/themes/$THEME_MODE"

        # Load FZF
        if [ -f "$fzf_file" ]; then
          export FZF_DEFAULT_OPTS="''${(j: :)''${(f)"$(<"$fzf_file")"}}"
        fi

        # Load NEWT (nmtui)
        if [ -f "$newt_file" ]; then
          export NEWT_COLORS="''${(j: :)''${(f)"$(<"$newt_file")"}}"
        fi
      }

      # Runs before every prompt to reload the theme vars (cheap, forkless).
      # Do not write THEME_MODE back to tmux: the dedicated remote session has
      # a fixed dark policy, independent of whichever pane was used last.
      # Capture/restore $? so this hook does not clobber the exit status
      # starship's own precmd reads.
      theme_precmd() {
        local ret=$?
        load_shell_themes
        return $ret
      }
      add-zsh-hook precmd theme_precmd

      # Run it once immediately on startup
      load_shell_themes

      ${lib.optionalString (peerHost != "") ''
        # SSH/mosh theme override (client side): wrap the bare `ssh ${peerHost}`
        # and `mosh ${peerHost}` forms so the peer picks up our current theme
        # for the session. Both hand the theme off via theme-hold, which just
        # exports THEME_MODE into the wrapped session process (tmux client or
        # login shell) and everything it forks (see theming.nix). Flags,
        # commands, and scp/rsync (which exec their binaries directly) fall
        # through untouched.
        ssh() {
          if [[ $# -eq 1 && "$1" == "${peerHost}" ]]; then
            local mode; mode=$(theme-mode 2>/dev/null || echo dark)
            command ssh -t "$1" "theme-hold $mode zsh -l"
          else
            command ssh "$@"
          fi
        }

        mosh() {
          if [[ $# -eq 1 && "$1" == "${peerHost}" ]]; then
            local mode; mode=$(theme-mode 2>/dev/null || echo dark)
            # mosh-server never times out by default and nothing else reaps
            # it, so this bounds orphans from SIGKILL-class client deaths
            # (crash, OOM, terminal window closed while offline). Deliberate
            # exits don't need it: mosh-client does a real shutdown handshake
            # on SIGHUP/SIGTERM and mosh-server exits in well under a second.
            # 24h is long enough that a suspended laptop reconnects fine.
            command mosh --server 'MOSH_SERVER_NETWORK_TMOUT=86400 mosh-server' "$1" -- theme-hold "$mode" zsh -l
          else
            command mosh "$@"
          fi
        }
      ''}

      # Accept next word from suggestion
      bindkey '^[f' forward-word  # Alt+F

      # Accept full suggestion
      bindkey '^F' autosuggest-accept

      # Initialize starship
      eval "$(starship init zsh)"
      source ${pkgs.zsh-vi-mode}/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh

      # Cursor blinking settings (set after zsh-vi-mode is loaded)
      # 1 = Blinking Block, 5 = Blinking Beam
      ZVM_NORMAL_MODE_CURSOR=$'\e[1 q'
      ZVM_INSERT_MODE_CURSOR=$'\e[5 q'
      ZVM_OPPEND_MODE_CURSOR=$'\e[5 q'

      # fzf shell integration (keybindings + completion). Loaded here instead of
      # via the oh-my-zsh "fzf" plugin so we can swallow the harmless
      # "can't change option: zle" that fzf 0.67.0's `--zsh` output prints while
      # snapshotting and restoring shell options. The FZF_DEFAULT_COMMAND block
      # preserves the behaviour the plugin used to provide.
      if (( ''${+commands[fzf]} )); then
        eval "$(fzf --zsh)" 2>/dev/null
        if [[ -z "$FZF_DEFAULT_COMMAND" ]]; then
          if (( ''${+commands[fd]} )); then
            export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
          elif (( ''${+commands[rg]} )); then
            export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git/*"'
          fi
        fi
      fi

      # zeno provides fuzzy completion, including changed-file completion for
      # git diff. Source it after fzf so its fallback can use fzf completion.
      # Do not call zeno-bind-default-keys: existing widgets keep their bindings.
      if [[ -z "''${DENO_DIR+x}" ]]; then
        export DENO_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/deno"
      fi
      # Reuse Deno's linked SQLite; loading @db/sqlite's bundled copy alongside
      # it crashes Deno 2.9 during Zeno startup.
      export DENO_SQLITE_PATH=${pkgs.sqlite.out}/lib/libsqlite3.so
      export ZENO_ROOT=${pkgs.zeno-zsh}/share/zeno.zsh
      source ${pkgs.zeno-zsh}/share/zeno.zsh/zeno.zsh

      # Yazi wrapper function - cd to directory on exit
      function y() {
        local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
        yazi "$@" --cwd-file="$tmp"
        IFS= read -r -d "" cwd < "$tmp"
        [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
        rm -f -- "$tmp"
      }

      # Silent yazi wrapper for keybinding
      function silent-y() {
        zle -I
        eval "y"
        zle reset-prompt
        if [[ $KEYMAP == "vicmd" ]]; then
          echo -ne "\e[1 q"
        else
          echo -ne "\e[5 q"
        fi
      }

      # Register widget
      zle -N silent-y

      # Keybindings for zsh-vi-mode
      function zvm_after_init() {
        # Bind for Insert Mode
        zvm_bindkey viins '^o' silent-y
        # zeno completion only; retain the existing bindings for all other widgets.
        zvm_bindkey viins '^I' zeno-completion
        # Bind for Normal Mode
        zvm_bindkey vicmd '^o' silent-y
        # Restore Ctrl+r for fzf history search
        zvm_bindkey viins '^R' fzf-history-widget
        # Dirhistory keybindings (Ctrl+arrow instead of Alt+arrow)
        zvm_bindkey viins '^[[1;5D' dirhistory_zle_dirhistory_back    # Ctrl+Left
        zvm_bindkey viins '^[[1;5C' dirhistory_zle_dirhistory_future  # Ctrl+Right
        zvm_bindkey viins '^[[1;5A' dirhistory_zle_dirhistory_up      # Ctrl+Up
        zvm_bindkey viins '^[[1;5B' dirhistory_zle_dirhistory_down    # Ctrl+Down
        zvm_bindkey vicmd '^[[1;5D' dirhistory_zle_dirhistory_back
        zvm_bindkey vicmd '^[[1;5C' dirhistory_zle_dirhistory_future
        zvm_bindkey vicmd '^[[1;5A' dirhistory_zle_dirhistory_up
        zvm_bindkey vicmd '^[[1;5B' dirhistory_zle_dirhistory_down
      }

      # Whai wrapper function
      whai() {
        LD_LIBRARY_PATH=$(nix-build "<nixpkgs>" -A stdenv.cc.cc.lib --no-out-link)/lib:$LD_LIBRARY_PATH command whai "$@"
      }

      # Whai alias wrapper
      function _whai_wrapper() {
        whai "$*"
      }

      # Symbol alias for whai (noglob prevents shell from expanding '?')
      alias ,='noglob _whai_wrapper'

      # System rebuild alias. /etc/nixos is the stable symlink to this checkout,
      # so this works from any directory.
      alias rebuild='sudo nixos-rebuild switch --flake /etc/nixos#system --impure'

      # Codex with unrestricted filesystem access.
      alias cdy='codex --yolo'

      # Claude Code with the mattpocock skills profile (separate CLAUDE_CONFIG_DIR).
      alias claude-matt='CLAUDE_CONFIG_DIR="$HOME/.config/claude-mattpocock" claude'

      # Claude Code through the isolated local GPT-5.6 gateway profile.
      alias clg='claude-gpt56'

      # Orchestrator sessions: a model plus its own top-level system prompt.
      # --dangerously-skip-permissions, not --permission-mode bypassPermissions:
      # the latter silently downgrades to the default mode until the bypass
      # disclaimer has been accepted interactively at least once.
      alias co='claude --dangerously-skip-permissions --model claude-opus-5 --append-system-prompt-file "$HOME/.config/claude/orchestrator-opus.md"'
      alias cf='claude --dangerously-skip-permissions --model claude-fable-5 --append-system-prompt-file "$HOME/.config/claude/orchestrator-fable.md"'

      # Claude Code profile launchers bypassing all permission checks.
      alias cly='claude --dangerously-skip-permissions'
      alias clty='claude-matt --dangerously-skip-permissions'
      alias clgy='claude-gpt56 --dangerously-skip-permissions'

      # Git push shortcuts.
      alias gp='git push'
      alias gpf='git push --force'

      # Git status shortcut.
      alias gs='git status'

      # Function to print a random poem with alignment
      function print_welcome_poem() {
        ${builtins.readFile ./print_poem.sh}
      }

      # Launch fastfetch on terminal open. A `sleep 0.1` used to sit here "to
      # let the terminal initialize", but foot sets the pty size before the
      # shell spawns, so the greeting renders correctly without it.
      fastfetch && print_welcome_poem && printf '\n'

      # Re-register zoxide's chpwd hook after the oh-my-zsh/plugin chpwd hooks
      # loaded above, so directory tracking keeps working (some plugins reassign
      # chpwd_functions and would otherwise drop zoxide's hook).
      add-zsh-hook -d chpwd __zoxide_hook 2>/dev/null
      add-zsh-hook chpwd __zoxide_hook
    '';

    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "sudo"
        "aliases"
        "alias-finder"
        "battery"
        "catimg"
        "gitfast"
        "extract"
        "zsh-interactive-cd"
        "direnv"
        "dircycle"
        "zsh-navigation-tools"
        "dirhistory"
        "wd"
      ];
    };

    syntaxHighlighting = {
      enable = true;
      # E-ink optimized syntax highlighting theme
      styles = {
        # Commands - bold to stand out as main element
        command = "bold";
        alias = "bold";
        builtin = "bold";
        function = "bold";
        # Paths - underline to show they're clickable/navigable
        path = "underline";
        path_pathseparator = "underline";
        # Arguments and strings - plain (normal weight)
        single-quoted-argument = "none";
        double-quoted-argument = "none";
        dollar-quoted-argument = "none";
        # Options - underline to distinguish from regular args
        single-hyphen-option = "underline";
        double-hyphen-option = "underline";
        # Special elements
        unknown-token = "none";
        reserved-word = "standout";
        # Globbing and patterns
        globbing = "bold,underline";
        history-expansion = "bold,underline";
        # Redirections
        redirection = "underline";
        # Comments
        comment = "none";
      };
    };

    autosuggestion.enable = true;
  };

  programs.zoxide = {
    enable = true;
    options = [ "--cmd cd" ];
  };
}
