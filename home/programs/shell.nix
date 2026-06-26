# Zsh Shell Configuration
# Managed by home-manager
{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    dotDir = config.home.homeDirectory;

    initContent = ''
      unsetopt BEEP
      KEYTIMEOUT=1
      export LS_COLORS="''${LS_COLORS}:ln=01;36:or=01;31:"

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

      # Define paths
      FZF_LINK="$HOME/.config/fzf/current_theme"
      NEWT_LINK="$HOME/.config/newt/current_theme"

      # Function to read links and export variables
      load_shell_themes() {
        # Load FZF
        if [ -f "$FZF_LINK" ]; then
           export FZF_DEFAULT_OPTS=$(tr '\n' ' ' < "$FZF_LINK")
        fi

        # Load NEWT (nmtui)
        if [ -f "$NEWT_LINK" ]; then
           export NEWT_COLORS=$(tr '\n' ' ' < "$NEWT_LINK")
        fi
      }

      # Add it to the precmd array (runs before every prompt)
      add-zsh-hook precmd load_shell_themes

      # Run it once immediately on startup
      load_shell_themes

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

      # System rebuild alias
      alias rebuild='sudo nixos-rebuild switch --flake /etc/nixos#andongni --impure'

      # Codex with unrestricted filesystem access.
      alias codexy='codex --yolo'

      # Function to print a random poem with alignment
      function print_welcome_poem() {
        ${builtins.readFile ./print_poem.sh}
      }

      # Launch fastfetch on terminal open (delay allows terminal to initialize)
      sleep 0.1 && fastfetch && print_welcome_poem && printf '\n'
    '';

    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "sudo"
        "fzf"
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
