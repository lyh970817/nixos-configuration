#!/usr/bin/env bash

# Drive a wl-screenrec recording: start, pause/resume, stop-and-save, and
# cancel-and-discard.
#
# A Hyprland bind and a rofi entry each fire one command and exit, so the
# session state lives in a file under $XDG_RUNTIME_DIR rather than in a daemon.
# Two capture modes, matching screenshot.sh:
#   screen - the focused monitor (default)
#   region - an interactively selected area (via slurp)
# Either one doubles as the pause/resume trigger: with a recording live it
# pauses, with one paused it resumes. `stop` finishes and keeps the file;
# `cancel` is the deliberate opposite, ending the recording and throwing every
# byte of it away.
#
# Pause is segmentation, not a signal. wl-screenrec 0.2.0 has no pause -- its
# only signal feature is `--history`, a SIGUSR1 replay buffer -- and
# SIGSTOP/SIGCONT is not a stand-in: frame timestamps come from the compositor
# clock, so a stopped-then-continued recorder emits one enormous frozen frame
# and wrecks the timing, while its Wayland buffers back up for as long as it is
# not reading. So pause finalizes the current segment and resume starts a new
# one with byte-identical capture parameters -- same output or geometry, same
# encoder, same streams -- which is what lets stop join them with ffmpeg's
# concat demuxer under `-c copy`. Nothing is ever re-encoded, and a recording
# that was never paused is a single segment that is simply renamed into place.

set -euo pipefail

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
# Line-based `key=value`; see write_state(). Empty means idle.
state_file="$runtime_dir/screen-record.state"
log_file="$runtime_dir/screen-record.log"
concat_list="$runtime_dir/screen-record.concat"
rec_dir="${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings"

# Encoding settings. Sessions here run 40-60 minutes and should land in the
# same ballpark as a Zoom or Teams meeting recording, roughly 300 MB - 1 GB an
# hour. Retune by editing these two constants; the arithmetic is:
#
#   video  200 kB/s = 1.6 Mbps  ~= 720 MB/hour
#   audio   16 kB/s = 128 kbps  ~=  58 MB/hour   (wl-screenrec's own default)
#   total                       ~= 780 MB/hour
#
# wl-screenrec's -b is BYTES per second, not bits, so its 5 MB default is
# 40 Mbps -- about 18 GB for one session, which is what this replaces. The
# unit suffix is mandatory rather than decoration: its parser rejects a bare
# `200000` with "no multiple".
#
# --max-fps is a ceiling, not a floor. wl-screenrec only copies a frame when
# the content changed, so a still screen still costs nothing; 15 is invisible
# on a screencast and buys the encoder a lot of room at this bitrate.
video_bitrate="200 kB"
max_fps=15

# Every notification carries the same synchronous hint, so mako replaces the
# previous one in place instead of stacking a column of them. That is what
# makes the optimistic-then-correct pattern in supervise() safe: a correction
# overwrites the message it is correcting.
notify() {
  notify-send -h string:x-canonical-private-synchronous:screen-record \
    "Screen recording" "$1"
}

log() {
  printf '[%s] %s\n' "$(date +%T)" "$*" >> "$log_file"
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

# st_state  recording | paused
# st_target final file this session will be saved as, chosen once at start
# st_mode   screen | region, for the notifications and for resume
# st_hw     1 while the hardware encoder is in use, 0 after the --no-hw fallback
# st_audio  1 while --audio is in use, 0 once it has been dropped
# st_pid    the live recorder, meaningful only while st_state=recording
# st_args   capture arguments, replayed verbatim on every resume
# st_segs   the segment files, in order; the last one is the current segment
#
# st_hw and st_audio are part of the session, not of one launch: every segment
# must be produced by the same encoder with the same set of streams, or the
# `-c copy` join in stop() has nothing valid to write.
st_state=""
st_target=""
st_mode=""
st_hw=""
st_audio=""
st_pid=""
st_args=()
st_segs=()

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

# Rewrite the state file from the st_* variables. Written to a sibling and
# renamed so a concurrent invocation reads either the old file or the new one,
# never half of one.
write_state() {
  local a s
  {
    printf 'state=%s\n' "$st_state"
    printf 'target=%s\n' "$st_target"
    printf 'mode=%s\n' "$st_mode"
    printf 'hw=%s\n' "$st_hw"
    printf 'audio=%s\n' "$st_audio"
    if [ -n "$st_pid" ]; then
      printf 'pid=%s\n' "$st_pid"
    fi
    for a in ${st_args[@]+"${st_args[@]}"}; do
      printf 'arg=%s\n' "$a"
    done
    for s in ${st_segs[@]+"${st_segs[@]}"}; do
      printf 'seg=%s\n' "$s"
    done
  } > "$state_file.new"
  mv -f "$state_file.new" "$state_file"
}

# Truncate rather than delete: the idle state needs no file removal, so this
# script never hands a path to rm.
clear_state() {
  : > "$state_file"
}

# Populate the st_* variables. Non-zero when there is no session, having first
# forgotten state left behind by a crash, a reboot, or a recycled PID.
load_state() {
  local key value line
  st_state=""; st_target=""; st_mode=""; st_hw=""; st_audio=""; st_pid=""
  st_args=(); st_segs=()
  [ -s "$state_file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      state) st_state="$value" ;;
      target) st_target="$value" ;;
      mode) st_mode="$value" ;;
      hw) st_hw="$value" ;;
      audio) st_audio="$value" ;;
      pid) st_pid="$value" ;;
      arg) st_args+=("$value") ;;
      seg) st_segs+=("$value") ;;
      # Anything else is a state file this version does not understand.
    esac
  done < "$state_file"

  # A structurally incomplete file is not a session, whatever else it says.
  case "$st_state" in
    recording | paused) ;;
    *)
      clear_state
      return 1
      ;;
  esac
  if [ -z "$st_target" ] || [ ${#st_segs[@]} -eq 0 ]; then
    clear_state
    return 1
  fi
  [ -n "$st_mode" ] || st_mode="screen"
  [ -n "$st_hw" ] || st_hw="1"
  [ -n "$st_audio" ] || st_audio="1"

  if [ "$st_state" = "recording" ] && ! is_recorder "$st_pid" "${st_segs[-1]}"; then
    # The recorder died without us asking it to: killed by hand, OOM, a crash.
    # Its segment is already on disk and finalized or not, so demote to paused
    # rather than discarding the session -- the user can then resume onto a
    # fresh segment or stop and keep whatever was captured. Silent by design:
    # every caller below ends in its own notification, which would replace this
    # one immediately anyway.
    log "recorder $st_pid vanished; demoting session to paused"
    st_state="paused"
    st_pid=""
    write_state
  fi
  return 0
}

# The state file still names $1 as the live recorder. Compare-and-swap for
# supervise(): between launching a recorder and checking that it survived, the
# user may have pressed pause, stop or cancel, and that newer decision wins.
state_still_owns() {
  local want="$1" line
  [ -s "$state_file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "pid=$want" ]; then
      return 0
    fi
  done < "$state_file"
  return 1
}

# ---------------------------------------------------------------------------
# Recording
# ---------------------------------------------------------------------------

segment_path() {
  printf '%s.part%03d.mp4\n' "${st_target%.mp4}" "$1"
}

# Start wl-screenrec on segment $1 in the background and set $pid. Returns as
# soon as the process exists; whether it survived is supervise()'s business.
launch() {
  local out="$1"
  # Identical on every segment of a session, which is the precondition for the
  # `-c copy` join in stop().
  local tune=(-b "$video_bitrate" --max-fps "$max_fps")
  if [ "$st_hw" != "1" ]; then
    tune+=(--no-hw)
  fi
  if [ "$st_audio" = "1" ]; then
    # Default capture device. On by default because a narrated 40-60 minute
    # screencast that turns out to be silent is only discovered an hour in.
    tune+=(--audio)
  fi
  # `env --default-signal=INT` is load-bearing, not decoration. Bash sets
  # SIGINT (and SIGQUIT) to SIG_IGN for a background job in a non-interactive
  # shell and the child inherits it -- measured as SigIgn 0x6 on a plain `cmd
  # &`, 0x4 with this reset. Without it the recorder would start with SIGINT
  # ignored and neither the stop nor the pause path below could ever reach it,
  # so every recording would have to be killed and every file would be a
  # corrupt container.
  # `env` execs in place, so $! is still the recorder's own PID.
  env --default-signal=INT wl-screenrec \
    ${st_args[@]+"${st_args[@]}"} "${tune[@]}" -f "$out" \
    >> "$log_file" 2>&1 &
  pid=$!
}

# Wait out the startup window and report whether the recorder we last launched
# is still alive. A VA-API encoder that cannot be opened, and an audio backend
# with no usable capture device, both abort within the first second.
survived() {
  sleep 2
  kill -0 "$pid" 2> /dev/null
}

# How the currently settled configuration differs from the ideal one, for the
# notification that reports a degraded start.
degraded_note() {
  if [ "$st_hw" = "1" ] && [ "$st_audio" != "1" ]; then
    printf 'no audio, no capture device available'
  elif [ "$st_hw" != "1" ] && [ "$st_audio" = "1" ]; then
    printf 'software encoding, no hardware encoder available'
  else
    printf 'software encoding and no audio'
  fi
}

# Send SIGINT and wait for the recorder to finalize its container. $1 is the
# number of 0.1s ticks to wait. Non-zero when it is still running afterwards.
#
# SIGINT, never SIGKILL: wl-screenrec has to flush and write the MP4 index on
# its way out, and a killed process leaves an unplayable file.
finalize_current() {
  local ticks="$1" seg="${st_segs[-1]}" i
  kill -INT "$st_pid" 2> /dev/null || true
  for i in $(seq 1 "$ticks"); do
    is_recorder "$st_pid" "$seg" || return 0
    sleep 0.1
  done
  ! is_recorder "$st_pid" "$seg"
}

# Watch the recorder we just launched and correct the optimistic notification
# only if it did not survive.
#
# This runs *after* the state file is written and the user has been told the
# recording is on, which is the whole point: a VA-API encoder that cannot be
# opened aborts within the first second, but making the first notification wait
# for that verdict cost every single recording a >=2s lag between the keypress
# and any feedback at all. The common case now notifies immediately and this
# function says nothing.
#
# $1 is "start" (which walks a degradation ladder) or "resume" (which does not
# -- see resume()).
supervise() {
  local phase="$1" rung hw audio
  if survived; then
    return 0
  fi
  # It died. Only act if nothing else has moved the session on since.
  if ! state_still_owns "$pid"; then
    return 0
  fi

  if [ "$phase" = "resume" ]; then
    # Keep the session: the earlier segments are still on disk and still
    # saveable, so drop back to paused instead of losing them.
    st_state="paused"
    st_pid=""
    write_state
    notify "Resume failed — see $log_file. Still paused with $(count_segments) segment(s)."
    exit 1
  fi

  # Degradation ladder, "<hw> <audio>", best first and starting one rung below
  # the ideal "1 1" that start() already tried. Two capabilities can each fail
  # independently, so this drops one at a time rather than both at once.
  #
  # wl-screenrec defaults to VA-API hardware encoding: mesa's radeonsi covers
  # the home desktop's amdgpu and intel-media-driver the laptop's Intel iGPU,
  # both via hardware.graphics (modules/hardware/video.nix). Dropping to a CPU
  # encode still beats a zero-byte file with no indication anything went wrong.
  # Audio is given up last and only after software encoding has been tried with
  # it, because a silent recording of a narrated session is the more expensive
  # loss -- and a host with no usable capture device would otherwise not record
  # at all now that --audio is on by default.
  for rung in "0 1" "1 0" "0 0"; do
    hw="${rung% *}"
    audio="${rung#* }"
    if [ "$hw" = "$st_hw" ] && [ "$audio" = "$st_audio" ]; then
      continue
    fi
    st_hw="$hw"
    st_audio="$audio"
    launch "${st_segs[-1]}"
    st_pid="$pid"
    write_state
    # Notified only once a rung has actually held, so a ladder walk costs one
    # correction rather than one per attempt.
    if survived; then
      notify "Recording $st_mode — $(degraded_note)"
      return 0
    fi
    if ! state_still_owns "$pid"; then
      return 0
    fi
  done

  clear_state
  notify "Failed to start — see $log_file"
  exit 1
}

start() {
  local mode="$1" output geometry
  mkdir -p "$rec_dir"
  st_mode="$mode"
  st_hw="1"
  st_audio="1"
  # Sortable stamp, matching the screenshot script's naming.
  st_target="$rec_dir/screenrecord_$(date +'%Y-%m-%d_%H-%M-%S').mp4"
  st_args=()

  case "$mode" in
    screen)
      # wl-screenrec records one output at a time; pick the focused monitor so
      # "screen" means the one under the cursor on a multi-head desktop. The
      # query must not be fatal: outside a Hyprland session hyprctl exits
      # non-zero, and under `set -o pipefail` that would abort here and leave
      # no recording and no notification. Fall back to wl-screenrec's own
      # default of the sole display instead. Pinning the output also matters
      # for resume: every segment must capture the same thing.
      output="$(hyprctl -j monitors 2> /dev/null | jq -r '.[] | select(.focused) | .name' 2> /dev/null)" || output=""
      if [ -n "$output" ]; then
        st_args+=(-o "$output")
      fi
      ;;
    region)
      # slurp exits non-zero when the selection is cancelled (Esc); bail
      # quietly instead of recording the whole screen by surprise.
      if ! geometry="$(slurp)"; then
        exit 0
      fi
      st_args+=(-g "$geometry")
      ;;
  esac

  : > "$log_file"
  st_segs=("$(segment_path 1)")
  launch "${st_segs[-1]}"
  st_state="recording"
  st_pid="$pid"
  write_state
  notify "Recording $mode — Super+I pauses, Super+Shift+I saves"
  supervise start
}

pause() {
  if ! finalize_current 100; then
    # A long segment can take a while to write its index. Keep the state so the
    # next trigger retries this pause instead of doing something else.
    notify "Still finalizing the segment — trigger again in a moment"
    exit 0
  fi
  st_state="paused"
  st_pid=""
  write_state
  notify "Paused after $(count_segments) segment(s) — Super+I resumes, Super+Shift+I saves"
}

resume() {
  st_segs+=("$(segment_path $((${#st_segs[@]} + 1)))")
  launch "${st_segs[-1]}"
  st_state="recording"
  st_pid="$pid"
  write_state
  notify "Resumed — recording $st_mode, segment ${#st_segs[@]}"
  # No degradation ladder here, deliberately. Every segment has to share one
  # codec, one pixel format and one set of streams for `-c copy` to join them,
  # so switching encoders or dropping the audio track mid-session would produce
  # a set of files that cannot be concatenated. Failing back to paused keeps
  # the earlier segments saveable instead.
  supervise resume
}

# ---------------------------------------------------------------------------
# Segments
# ---------------------------------------------------------------------------

# Echo the segments worth keeping, one per line: a segment that exists, is a
# regular file rather than a symlink, and actually got bytes written to it. A
# zero-byte segment is what a recorder that died on startup leaves behind, and
# feeding one to the concat demuxer fails the whole join.
live_segments() {
  local s
  for s in ${st_segs[@]+"${st_segs[@]}"}; do
    if [ -f "$s" ] && [ ! -L "$s" ] && [ -s "$s" ]; then
      printf '%s\n' "$s"
    fi
  done
}

count_segments() {
  live_segments | wc -l
}

# Join $@ into $st_target with the concat demuxer under stream copy.
concat_segments() {
  local s esc
  : > "$concat_list"
  for s in "$@"; do
    # The demuxer's own quoting: a literal ' inside a quoted path is '\''.
    esc="${s//\'/\'\\\'\'}"
    printf "file '%s'\n" "$esc" >> "$concat_list"
  done
  # -safe 0 because the list holds absolute paths; -c copy because the segments
  # were produced by one encoder with one set of parameters and must not be
  # re-encoded.
  ffmpeg -hide_banner -loglevel error -y \
    -f concat -safe 0 -i "$concat_list" -c copy "$st_target" >> "$log_file" 2>&1
}

# Move one file this script created to the desktop trash.
#
# Deliberately not `rm`: `gio trash` is reversible (`gio trash --restore`), so a
# mis-fired cancel costs a trip to the wastebasket rather than the recording,
# and the segment cleanup after a successful join is a deletion too and goes
# the same way. $path is not free-form input -- start() and resume() wrote it
# -- but it is re-checked here, immediately before the move, so a stale or
# hand-edited state file cannot aim this at anything else.
#
# 0 trashed, 1 there was nothing to trash, 2 refused or failed.
trash_one() {
  local path="$1" base
  base="${path##*/}"
  # Rejects an empty path, any directory but the recordings directory, and any
  # `..` component: $base can contain no slash, so a path that still equals
  # "$rec_dir/$base" is a direct child of $rec_dir under that literal name.
  if [ -z "$base" ] || [ "$path" != "$rec_dir/$base" ]; then
    notify "Refusing to discard unexpected path: $path"
    return 2
  fi
  # Covers both shapes this script writes: the final screenrecord_<stamp>.mp4
  # and its screenrecord_<stamp>.partNNN.mp4 segments.
  case "$base" in
    screenrecord_*.mp4) ;;
    *)
      notify "Refusing to discard unexpected file: $base"
      return 2
      ;;
  esac
  if [ -L "$path" ] || [ ! -f "$path" ]; then
    # Never follow a symlink, and a segment that was never written has nothing
    # to throw away.
    return 1
  fi
  if gio trash -- "$path"; then
    return 0
  fi
  notify "Discard failed — $path kept"
  return 2
}

# Trash every segment of this session. Non-zero if any was refused or failed.
trash_all_segments() {
  local s rc=0 status
  for s in ${st_segs[@]+"${st_segs[@]}"}; do
    status=0
    trash_one "$s" || status=$?
    if [ "$status" = "2" ]; then
      rc=1
    fi
  done
  return "$rc"
}

# ---------------------------------------------------------------------------
# Terminal actions
# ---------------------------------------------------------------------------

stop() {
  local segs=() n
  if [ "$st_state" = "recording" ] && ! finalize_current 100; then
    # Keep the state so the next trigger resumes this stop instead of starting
    # a second, overlapping recording on top of it.
    notify "Still finalizing — trigger again in a moment"
    exit 0
  fi

  mapfile -t segs < <(live_segments)
  n=${#segs[@]}

  if [ "$n" -eq 0 ]; then
    clear_state
    trash_all_segments || true
    notify "Stopped, but nothing was written — see $log_file"
    return 0
  fi

  if [ "$n" -eq 1 ]; then
    # Never paused, or paused with everything else empty: one rename inside the
    # recordings directory, no concat and no re-read of the data. `mv -n` is
    # not the guard here -- it skips silently and still exits 0 -- so the
    # collision is checked outright, even though a per-second timestamp and a
    # recording that takes longer than a second make one all but impossible.
    if [ ! -e "$st_target" ] && [ ! -L "$st_target" ] && mv -- "${segs[0]}" "$st_target"; then
      clear_state
      # Any *other* segment here was empty, so it is a leftover to clean up.
      # The renamed one is no longer at its old path and is simply skipped.
      trash_all_segments || true
      notify "Saved to $st_target"
      return 0
    fi
    notify "Could not move ${segs[0]} to $st_target — segment kept"
    exit 1
  fi

  notify "Joining $n segments…"
  if ! concat_segments "${segs[@]}"; then
    # Keep both the segments and the state: the recording is not lost, it is
    # just still in pieces, and a second trigger can retry the join.
    notify "Join failed — $n segments kept in $rec_dir, see $log_file"
    exit 1
  fi
  clear_state
  if trash_all_segments; then
    notify "Saved to $st_target — joined $n segments"
  else
    notify "Saved to $st_target — joined $n segments, some could not be cleaned up"
  fi
}

# Stop the running recording and throw every segment away.
#
# Unlike stop(), no container ever has to end up valid, so this does not wait
# out a long index flush: SIGINT first, so wl-screenrec still releases the
# encoder tidily, then SIGKILL once a short grace has passed. The
# `env --default-signal=INT` in launch() is what makes that first SIGINT
# deliverable at all.
cancel() {
  local i n
  if [ "$st_state" = "recording" ]; then
    if ! finalize_current 20; then
      kill -KILL "$st_pid" 2> /dev/null || true
      for i in $(seq 1 20); do
        is_recorder "$st_pid" "${st_segs[-1]}" || break
        sleep 0.1
      done
    fi
    if is_recorder "$st_pid" "${st_segs[-1]}"; then
      # Still running: keep the files and the state rather than trash something
      # another process still holds open.
      notify "Could not stop the recorder — segments kept"
      exit 1
    fi
  fi
  n=$(count_segments)
  # Cleared before the trashing: the recorder is gone either way, so a refusal
  # below must not leave a wedged session behind. It notifies loudly instead.
  clear_state
  if ! trash_all_segments; then
    exit 1
  fi
  if [ "$n" -eq 0 ]; then
    notify "Recording discarded (nothing had been written)"
  else
    notify "Recording discarded — $n segment(s) moved to the trash"
  fi
}

# ---------------------------------------------------------------------------

mode="${1:-screen}"
case "$mode" in
  screen | region | stop | cancel) ;;
  *)
    echo "Usage: screen-record {screen|region|stop|cancel}" >&2
    exit 1
    ;;
esac

if load_state; then
  case "$mode" in
    stop) stop ;;
    cancel) cancel ;;
    # Both capture modes are the one pause/resume trigger, so the bind that
    # starts a recording is also the bind that suspends and continues it.
    # Whichever mode the session was started in is the one that resumes.
    *)
      if [ "$st_state" = "recording" ]; then
        pause
      else
        resume
      fi
      ;;
  esac
else
  case "$mode" in
    # Stopping or cancelling with nothing running is harmless, not an error.
    stop) notify "Nothing to stop — no recording in progress" ;;
    cancel) notify "Nothing to cancel — no recording in progress" ;;
    *) start "$mode" ;;
  esac
fi
