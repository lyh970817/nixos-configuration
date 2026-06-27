# Tmux Configuration
# Managed by home-manager
# Original: ~/.tmux.conf
{ config, pkgs, ... }:

{
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

      # --- Pane Management ---
      # Horizontal Split: Alt + Enter
      bind -n M-Enter split-window -h -c "#{pane_current_path}"

      # Enable extended keys so tmux recognizes the code sent by Alacritty
      set -s extended-keys on
      set -as terminal-features 'xterm*:extkeys'

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

      # Resize panes with Alt + Arrow keys
      bind -n M-Left  resize-pane -L 2
      bind -n M-Right resize-pane -R 2
      bind -n M-Up    resize-pane -U 2
      bind -n M-Down  resize-pane -D 2

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

      # Bind 'y' to copy to Wayland clipboard
      bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "wl-copy"

      # 4. Mouse Dragging
      # When you release the mouse click after selecting, copy to clipboard automatically
      bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "wl-copy"

      # --- Matrix Green Theme (10% Dimmer Colors) ---

      # 1. Basic Colors (Bright Green text on Black background)
      set -g status-style bg=black,fg=#4AB34D

      # 2. Pane Borders
      # Inactive pane border: Verse Green (subtle, dark green)
      set -g pane-border-style fg=#126D15
      # Active pane border: Apple Green (bright, distinct)
      set -g pane-active-border-style fg=#4AB34D

      # 3. Status Bar - Window List
      # Inactive windows: Apple Green text on black background
      setw -g window-status-style fg=#4AB34D,bg=black
      # Active window: Black text on Apple Green background (Inverted Block)
      setw -g window-status-current-style fg=black,bg=#4AB34D,bold

      # 4. Command/Message Line (The bottom bar when you type commands)
      set -g message-style fg=black,bg=#4AB34D,bold

      # 5. Selection Mode (When highlighting text)
      set -g mode-style fg=black,bg=#3CA23F

      set -ag terminal-overrides ",alacritty:RGB"
    '';
  };
}
