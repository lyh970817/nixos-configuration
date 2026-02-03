unsetopt BEEP

function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

function silent-y() {
  # 'zle -I' invalidates the current prompt display to allow output
  zle -I
  
  # Run the command "y". 
  # We use 'eval' so that if 'y' is an alias (e.g. alias y="yarn"), it still works.
  eval "y"

  # Redraw the prompt cleanly after the command finishes
  zle reset-prompt

  # --- THE FIX ---
  # Check which mode we are in and force the correct cursor shape
  # \e[2 q = Block (Normal/Command Mode)
  # \e[6 q = Beam (Insert Mode)
  
  if [[ $KEYMAP == "vicmd" ]]; then
    echo -ne "\e[2 q"
  else
    echo -ne "\e[6 q"
  fi
}

# 2. Register the widget
zle -N silent-y

# bindkey -s "^o" "y\n"

function zvm_after_init() {
# Bind for Insert Mode
  zvm_bindkey viins '^o' silent-y
  
  # Bind for Normal Mode
  zvm_bindkey vicmd '^o' silent-y

# Restore Ctrl+r for fzf history search
  # 'viins' = Insert Mode
  zvm_bindkey viins '^R' fzf-history-widget
}

whai() {
 LD_LIBRARY_PATH=$(nix-build "<nixpkgs>" -A stdenv.cc.cc.lib --no-out-link)/lib:$LD_LIBRARY_PATH command whai "$@"
}

# 1. The actual logic
function _whai_wrapper() {
    # "$*" takes all arguments and wraps them in one big string with quotes
    whai "$*"
}

# 2. The symbol alias
# 'noglob' stops the shell from freaking out if you type a '?' in your query
alias ,='noglob _whai_wrapper'
