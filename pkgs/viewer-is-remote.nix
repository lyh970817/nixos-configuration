# Exits 0 when the human is at the far end of a mosh link, i.e. when this
# machine's own screen is not the one being looked at. Shared by every opener
# that has to decide between painting a local window and pushing to the peer;
# a second copy of this detection would drift.
{
  writeShellApplication,
  tmux,
  procps,
  coreutils,
  gawk,
}:

writeShellApplication {
  name = "viewer-is-remote";
  runtimeInputs = [
    tmux
    procps
    coreutils
    gawk
  ];
  text = ''
    # Walk a process ancestry looking for mosh-server.
    ancestry_has_mosh() {
      local pid="$1" comm
      while [ -n "$pid" ]; do
        case "$pid" in
          *[!0-9]*) return 1 ;;
        esac
        [ "$pid" -gt 1 ] || return 1
        comm="$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
        if [ "$comm" = "mosh-server" ]; then
          return 0
        fi
        pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
      done
      return 1
    }

    # Two shapes, because the two entry points differ: `home-terminal` runs
    # tmux on the far side (session "remote"), while the `mosh` shell function
    # just runs `zsh -l` with no tmux at all.
    viewer_is_remote() {
      # No tmux: the caller's own ancestry reaches mosh-server directly.
      if ancestry_has_mosh "$$"; then
        return 0
      fi

      # Under tmux the pane's shell descends from the tmux server, not from
      # mosh, so the ancestry above stops short. Ask tmux which clients are
      # attached and test those instead. Control-mode clients (editor and
      # agent integrations) are skipped -- nobody is looking at those.
      [ -n "''${TMUX:-}" ] || return 1

      local session pid
      session="$(tmux display-message -p '#{session_name}' 2>/dev/null)" || return 1

      while read -r pid; do
        if ancestry_has_mosh "$pid"; then
          return 0
        fi
      done < <(
        tmux list-clients -t "$session" \
          -F '#{client_control_mode} #{client_pid}' 2>/dev/null \
          | awk '$1 == 0 { print $2 }'
      )

      return 1
    }

    viewer_is_remote
  '';
}
