#!/usr/bin/env bash

# Toggle a wl-screenrec screen recording.
#
# The rofi launcher and a Hyprland bind both fire one command and exit, so a
# stateful recorder has to be a toggle: the first invocation starts a
# recording, the next one stops it. Two modes, matching screenshot.sh:
#   screen - the focused monitor (default)
#   region - an interactively selected area (via slurp)
# Stopping takes no argument; whichever mode is running is what stops.

set -euo pipefail

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
# Two lines: the recorder's PID, then the file it is writing. Empty means idle.
state_file="$runtime_dir/screen-record.state"
log_file="$runtime_dir/screen-record.log"

notify() {
  notify-send -h string:x-canonical-private-synchronous:screen-record \
    "Screen recording" "$1"
}

# True when PID $1 is still the recorder writing file $2.
#
# The PID comes from our own state file and is then confirmed by reading that
# one process's argv for the exact output path we handed it. Nothing is ever
# matched across the process table: a `pgrep -f wl-screenrec` also matches this
# very script -- the mode argument puts the pattern in our own argv -- so a
# pattern-based toggle would find, and then kill, itself. Matching the unique
# timestamped path also rules out a recycled PID after a crash or a reboot, and
# does not care whether the recorder is a bare binary or a wrapper script.
is_recorder() {
  local pid="${1:-}" want="${2:-}" arg
  [ -n "$pid" ] && [ -n "$want" ] || return 1
  [ -r "/proc/$pid/cmdline" ] || return 1
  while IFS= read -r -d '' arg; do
    if [ "$arg" = "$want" ]; then
      return 0
    fi
  done < "/proc/$pid/cmdline"
  return 1
}

# Populate rec_pid/rec_file from the state file. Non-zero when nothing is
# recording, having first forgotten state left behind by a crash, a reboot, or
# a recycled PID.
load_state() {
  rec_pid=""
  rec_file=""
  [ -s "$state_file" ] || return 1
  {
    read -r rec_pid || true
    read -r rec_file || true
  } < "$state_file"
  if is_recorder "$rec_pid" "$rec_file"; then
    return 0
  fi
  # Truncate rather than delete: the idle state needs no file removal, so this
  # script never hands a path to rm.
  : > "$state_file"
  return 1
}

# Start wl-screenrec in the background and report whether it survived startup.
# Sets $pid on success.
launch() {
  # `env --default-signal=INT` is load-bearing, not decoration. Bash sets
  # SIGINT (and SIGQUIT) to SIG_IGN for a background job in a non-interactive
  # shell and the child inherits it -- measured as SigIgn 0x6 on a plain `cmd
  # &`, 0x4 with this reset. Without it the recorder would start with SIGINT
  # ignored and the stop path below could never reach it, so every recording
  # would have to be killed and every file would be a corrupt container.
  # `env` execs in place, so $! is still the recorder's own PID.
  env --default-signal=INT wl-screenrec "$@" -f "$file" >> "$log_file" 2>&1 &
  pid=$!
  # A VA-API encoder that cannot be opened aborts within the first second.
  sleep 2
  kill -0 "$pid" 2>/dev/null
}

start() {
  local mode="$1" output geometry encoder
  local dir="${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings"
  mkdir -p "$dir"
  # Sortable stamp, matching the screenshot script's naming.
  file="$dir/screenrecord_$(date +'%Y-%m-%d_%H-%M-%S').mp4"

  local args=()
  case "$mode" in
    screen)
      # wl-screenrec records one output at a time; pick the focused monitor so
      # "screen" means the one under the cursor on a multi-head desktop. This
      # is a read-only query, so it needs no hypr-ipc dialect handling -- but it
      # must not be fatal: outside a Hyprland session hyprctl exits non-zero,
      # and under `set -o pipefail` that would abort here and leave no
      # recording and no notification. Fall back to wl-screenrec's own default
      # of the sole display instead.
      output="$(hyprctl -j monitors 2> /dev/null | jq -r '.[] | select(.focused) | .name' 2> /dev/null)" || output=""
      if [ -n "$output" ]; then
        args+=(-o "$output")
      fi
      ;;
    region)
      # slurp exits non-zero when the selection is cancelled (Esc); bail
      # quietly instead of recording the whole screen by surprise.
      if ! geometry="$(slurp)"; then
        exit 0
      fi
      args+=(-g "$geometry")
      ;;
  esac

  : > "$log_file"
  # wl-screenrec defaults to VA-API hardware encoding. The home desktop's
  # amdgpu has mesa's radeonsi VA-API driver, but the shared mesa build ships
  # no Intel VA-API driver, so the laptop may have no usable hardware encoder.
  # Fall back to the CPU encoder rather than leaving a zero-byte file and no
  # indication that anything went wrong.
  if launch "${args[@]}"; then
    encoder="hardware"
  elif launch "${args[@]}" --no-hw; then
    encoder="software"
  else
    notify "Failed to start — see $log_file"
    exit 1
  fi

  printf '%s\n%s\n' "$pid" "$file" > "$state_file"
  notify "Recording $mode ($encoder encoding). Trigger again to stop."
}

stop() {
  # SIGINT, never SIGKILL: wl-screenrec has to flush and finalize the MP4
  # container on its way out, and a killed process leaves an unplayable file.
  kill -INT "$rec_pid" 2> /dev/null || true
  local i
  for i in $(seq 1 100); do
    is_recorder "$rec_pid" "$rec_file" || break
    sleep 0.1
  done
  if is_recorder "$rec_pid" "$rec_file"; then
    # A long recording can take a while to write its index. Keep the state so
    # the next trigger resumes this stop instead of starting a second,
    # overlapping recording on top of it.
    notify "Still finalizing $rec_file"
    exit 0
  fi
  : > "$state_file"
  if [ -s "$rec_file" ]; then
    notify "Saved to $rec_file"
  else
    notify "Stopped, but nothing was written — see $log_file"
  fi
}

mode="${1:-screen}"
case "$mode" in
  screen | region) ;;
  *)
    echo "Usage: screen-record {screen|region}" >&2
    exit 1
    ;;
esac

if load_state; then
  stop
else
  start "$mode"
fi
