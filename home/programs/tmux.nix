# Tmux Configuration
# Managed by home-manager
# Original: ~/.tmux.conf
{ config, pkgs, ... }:

let
  scratchNote = pkgs.writeShellScript "tmux-scratch-note" ''
    set -eu

    direction="''${1:?missing split direction}"
    target_pane="''${2:?missing target pane}"
    pane_path="''${3:?missing pane path}"
    scratch_dir="''${SCRATCH_DIR:-$HOME/.scratch}"

    case "$direction" in
      horizontal)
        split_flag="-h"
        ;;
      vertical)
        split_flag="-v"
        ;;
      *)
        echo "unknown split direction: $direction" >&2
        exit 2
        ;;
    esac

    ${pkgs.coreutils}/bin/mkdir -p "$scratch_dir"
    ${pkgs.coreutils}/bin/chmod 700 "$scratch_dir"

    stamp="$(${pkgs.coreutils}/bin/date +%Y-%m-%d-%H%M)"
    note="$scratch_dir/$stamp.md"
    suffix=1

    while [ -e "$note" ]; do
      note="$scratch_dir/$stamp-$suffix.md"
      suffix=$((suffix + 1))
    done

    : > "$note"
    ${pkgs.tmux}/bin/tmux split-window "$split_flag" -t "$target_pane" -c "$pane_path" "nvim '$note'"
  '';

  # Copy stdin to the Wayland clipboard and also emit OSC 52 with an explicit
  # "c" target to every attached client tty. tmux's own set-clipboard emission
  # uses an empty target field, which mosh silently drops, so copies made over
  # a mosh session never reached the connecting machine's clipboard.
  osc52Copy = pkgs.writeShellScriptBin "osc52-copy" ''
    buf="$(${pkgs.coreutils}/bin/mktemp)"
    trap '${pkgs.coreutils}/bin/rm -f "$buf"' EXIT
    ${pkgs.coreutils}/bin/cat > "$buf"
    ${pkgs.wl-clipboard}/bin/wl-copy < "$buf" 2>/dev/null || true
    b64="$(${pkgs.coreutils}/bin/base64 -w0 < "$buf")"
    for client_tty in $(${pkgs.tmux}/bin/tmux list-clients -F "#{client_tty}"); do
      if [ -w "$client_tty" ]; then
        printf '\033]52;c;%s\007' "$b64" > "$client_tty" || true
      fi
    done
  '';
in
{
  home.packages = [ osc52Copy ];

  programs.tmux = {
    enable = true;
    terminal = "tmux-256color"; # Use screen-256color or tmux-256color
    historyLimit = 1000000;
    escapeTime = 10; # Reduced from default 500 for better responsiveness
    mouse = true;
    keyMode = "vi"; # Enables Vi-style keys for copy mode
    focusEvents = true; # Enables focus-events on
    baseIndex = 1;
    plugins = with pkgs.tmuxPlugins; [
      {
        plugin = tmux-thumbs;
      }
    ];
    extraConfig = ''
      # Remove the plugin's default prefix binding and expose it only in copy mode.
      unbind Space

      set -g allow-passthrough on

      # Clear the earlier user-level update-environment setting when this
      # config reloads in an existing server. The default list does not include
      # THEME_MODE, so attaches cannot overwrite the fixed remote session.
      set -gu update-environment

      # Emit OSC 52 on copy so copy-mode selections reach the local terminal's
      # clipboard over mosh/SSH (the wl-copy pipe only sets the local host's
      # Wayland clipboard). Requires advertising the terminal clipboard feature.
      set -g set-clipboard on
      set -as terminal-features '*:clipboard'

      # Use C-a as the tmux prefix so C-b remains available for copy-mode paging.
      set -g prefix C-a
      unbind -T prefix C-b
      bind -T prefix C-a send-prefix

      # --- Pane Management ---
      # Horizontal Split: Alt + Enter
      bind -n M-Enter split-window -h -c "#{pane_current_path}"

      # Scratch notes: create a timestamped Markdown file in $SCRATCH_DIR and
      # open it in Neovim in a split from the current tmux pane.
      bind -n C-1 run-shell -b "${scratchNote} horizontal #{q:pane_id} #{q:pane_current_path}"
      bind -n C-S-1 run-shell -b "${scratchNote} vertical #{q:pane_id} #{q:pane_current_path}"

      # Enable extended keys so tmux recognizes the code sent by Alacritty
      set -s extended-keys on
      set -as terminal-features 'xterm*:extkeys'

      # Pass Shift+Enter through to Codex as CSI-u. Without this explicit root
      # binding, tmux can collapse it back to Enter and submit the composer.
      bind -n S-Enter send-keys Escape "[13;2u"

      # Bind the specific escape code to your desired action
      bind -n S-F10 split-window -v -c "#{pane_current_path}"

      # Close Pane: Alt + q
      bind -n M-q kill-pane

      bind -n M-f resize-pane -Z

      # --- Window Navigation ---
      # Alt + 1..9 switches to that tmux window, creating it in the current
      # directory if the slot does not exist. Alt + 0 targets window 10.
      bind -n M-1 run-shell "tmux select-window -t '#{session_id}:=1' 2>/dev/null || tmux new-window -t '#{session_id}:=1' -c #{q:pane_current_path}"
      bind -n M-2 run-shell "tmux select-window -t '#{session_id}:=2' 2>/dev/null || tmux new-window -t '#{session_id}:=2' -c #{q:pane_current_path}"
      bind -n M-3 run-shell "tmux select-window -t '#{session_id}:=3' 2>/dev/null || tmux new-window -t '#{session_id}:=3' -c #{q:pane_current_path}"
      bind -n M-4 run-shell "tmux select-window -t '#{session_id}:=4' 2>/dev/null || tmux new-window -t '#{session_id}:=4' -c #{q:pane_current_path}"
      bind -n M-5 run-shell "tmux select-window -t '#{session_id}:=5' 2>/dev/null || tmux new-window -t '#{session_id}:=5' -c #{q:pane_current_path}"
      bind -n M-6 run-shell "tmux select-window -t '#{session_id}:=6' 2>/dev/null || tmux new-window -t '#{session_id}:=6' -c #{q:pane_current_path}"
      bind -n M-7 run-shell "tmux select-window -t '#{session_id}:=7' 2>/dev/null || tmux new-window -t '#{session_id}:=7' -c #{q:pane_current_path}"
      bind -n M-8 run-shell "tmux select-window -t '#{session_id}:=8' 2>/dev/null || tmux new-window -t '#{session_id}:=8' -c #{q:pane_current_path}"
      bind -n M-9 run-shell "tmux select-window -t '#{session_id}:=9' 2>/dev/null || tmux new-window -t '#{session_id}:=9' -c #{q:pane_current_path}"
      bind -n M-0 run-shell "tmux select-window -t '#{session_id}:=10' 2>/dev/null || tmux new-window -t '#{session_id}:=10' -c #{q:pane_current_path}"

      # --- Pane Navigation ---
      # Use Alt + vim keys to switch panes
      bind -n M-h select-pane -L
      bind -n M-j select-pane -D
      bind -n M-k select-pane -U
      bind -n M-l select-pane -R

      set -g status off
      set -g pane-border-lines heavy
      set -g pane-border-status off

      # Bind Alt+Shift+h/j/k/l to swap the current pane with the neighbor
      bind -n M-H swap-pane -t '{left-of}' \; select-pane -t '{left-of}'
      bind -n M-J swap-pane -t '{down-of}' \; select-pane -t '{down-of}'
      bind -n M-K swap-pane -t '{up-of}'   \; select-pane -t '{up-of}'
      bind -n M-L swap-pane -t '{right-of}' \; select-pane -t '{right-of}'

      bind -n M-v copy-mode

      # 2. Enable Vi-style keys for copy mode
      # set-window-option -g mode-keys vi

      # 3. Key Bindings
      # Bind 'v' to start selection (Vi style)
      bind -T copy-mode-vi v send-keys -X begin-selection

      # Use f in copy mode to invoke tmux-thumbs on the currently visible content.
      bind -T copy-mode-vi f thumbs-pick

      # Page through scrollback only after copy mode is active.
      bind -T copy-mode-vi C-b send-keys -X page-up
      bind -T copy-mode-vi C-u send-keys -X page-up
      bind -T copy-mode-vi C-d send-keys -X page-down
      bind -T copy-mode-vi C-f send-keys -X page-down

      # Bind 'y' to copy to Wayland clipboard (and OSC 52 for mosh/SSH clients)
      bind -T copy-mode-vi y send-keys -X copy-pipe "${osc52Copy}/bin/osc52-copy"

      # 4. Mouse Dragging
      # When you release the mouse click after selecting, copy to clipboard automatically
      bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe "${osc52Copy}/bin/osc52-copy"

      # Keep the established green tmux colors in light sessions; only dark
      # sessions become VT220 amber.
      %if "#{==:#{E:THEME_MODE},light}"
        set -g status-style bg=black,fg=#4AB34D
        set -g pane-border-style fg=#126D15
        set -g pane-active-border-style fg=#4AB34D
        setw -g window-status-style fg=#4AB34D,bg=black
        setw -g window-status-current-style fg=black,bg=#4AB34D,bold
        set -g message-style fg=black,bg=#4AB34D,bold
        set -g mode-style fg=black,bg=#3CA23F
      %else
        set -g status-style bg=#080705,fg=#D99B32
        set -g pane-border-style fg=#2A2011
        set -g pane-active-border-style fg=#D99B32
        setw -g window-status-style fg=#D99B32,bg=#080705
        setw -g window-status-current-style fg=#080705,bg=#D99B32,bold
        set -g message-style fg=#080705,bg=#D99B32,bold
        set -g mode-style fg=#080705,bg=#BE842A
      %endif

      set -ag terminal-overrides ",alacritty:RGB"
    '';
  };
}
