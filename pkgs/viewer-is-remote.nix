# Exits 0 when the human is at the far end of a mosh link, i.e. when this
# machine's own screen is not the one being looked at. Shared by every opener
# that has to decide between painting a local window and pushing to the peer;
# a second copy of this detection would drift.
{
  writeShellApplication,
  tmux,
  herdr,
  jq,
  procps,
  coreutils,
  gawk,
}:

writeShellApplication {
  name = "viewer-is-remote";
  runtimeInputs = [
    tmux
    herdr
    jq
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

    proc_starttime() {
      local proc_stat proc_fields
      proc_stat="$(<"/proc/$1/stat")" || return 1
      proc_fields="''${proc_stat##*) }"
      # shellcheck disable=SC2086 # split the post-comm stat fields by design
      set -- $proc_fields
      case "''${20:-}" in
        "" | *[!0-9]*) return 1 ;;
      esac
      printf '%s\n' "''${20}"
    }

    trusted_dir() {
      local path="$1" uid="$2"
      [ -d "$path" ] && [ ! -L "$path" ] \
        && [ "$(stat -c '%u:%a' "$path" 2>/dev/null)" = "$uid:700" ]
    }

    # A Herdr server is shared by local and remote attachments, so its name
    # alone cannot identify who is viewing it. The remote client creates one
    # PID/starttime lease for each live mosh attachment; compare starttime to
    # reject both stale files and recycled PIDs without deleting foreign state.
    has_remote_view_lease() {
      local uid runtime_dir lease_dir lease pid_line starttime_line pid starttime actual_starttime
      local -a lease_lines
      uid="$(id -u)"
      runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$uid}"
      trusted_dir "$runtime_dir" "$uid" || return 1
      lease_dir="$runtime_dir/herdr-remote-view"
      trusted_dir "$lease_dir" "$uid" || return 1

      for lease in "$lease_dir"/*; do
        [ -f "$lease" ] && [ ! -L "$lease" ] || continue
        [ "$(stat -c '%u:%a' "$lease" 2>/dev/null)" = "$uid:600" ] || continue
        mapfile -t lease_lines < "$lease" || continue
        [ "''${#lease_lines[@]}" -eq 2 ] || continue
        pid_line="''${lease_lines[0]}"
        starttime_line="''${lease_lines[1]}"
        case "$pid_line:$starttime_line" in
          pid=*:starttime=*) ;;
          *) continue ;;
        esac
        pid="''${pid_line#pid=}"
        starttime="''${starttime_line#starttime=}"
        case "$pid:$starttime" in
          *[!0-9:]* | :* | *:) continue ;;
        esac
        [ -r "/proc/$pid/stat" ] || continue
        actual_starttime="$(proc_starttime "$pid" 2>/dev/null || true)"
        [ "$actual_starttime" = "$starttime" ] || continue
        return 0
      done

      return 1
    }

    herdr_pane_is_remote() {
      [ -n "''${HERDR_SOCKET_PATH:-}" ] || return 1
      herdr session list --json 2>/dev/null \
        | jq -e --arg socket "$HERDR_SOCKET_PATH" '
          (.sessions | type == "array")
          and any(
            .sessions[];
            .name == "remote"
            and .running == true
            and .socket_path == $socket
          )
        ' >/dev/null
    }

    # Direct mosh shells and any remaining tmux sessions need different checks:
    # the former descend from mosh-server, while the latter need their attached
    # client PIDs inspected.
    viewer_is_remote() {
      # No tmux: the caller's own ancestry reaches mosh-server directly.
      if ancestry_has_mosh "$$"; then
        return 0
      fi

      # Herdr panes are children of the persistent server, not of mosh. Match
      # the injected socket to the named remote session, then require a live
      # remote-view lease; HERDR_SESSION and process-name guesses are not a
      # trustworthy indication of who is attached. A final client can exit
      # after this check, so one opener may still route remotely once.
      if herdr_pane_is_remote && has_remote_view_lease; then
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
