#!/usr/bin/env bash

# Drive a wl-screenrec recording: start, pause/resume, stop-and-save,
# drop-the-last-take, and cancel-and-discard.
#
# A Hyprland bind and a rofi entry each fire one command and exit, so the
# session state lives in a file under $XDG_RUNTIME_DIR rather than in a daemon.
# Two capture modes, matching screenshot.sh:
#   screen - the focused monitor (default)
#   region - an interactively selected area (via slurp)
# Either one doubles as the pause/resume trigger: with a recording live it
# pauses, with one paused it resumes. `stop` finishes and keeps the file;
# `cancel` is the deliberate opposite, ending the recording and throwing every
# byte of it away. `drop-segment` is the same discard at the granularity of one
# segment: it throws away the most recent take and leaves the rest of the
# session paused and saveable.
#
# Pause is segmentation, not a signal. wl-screenrec 0.2.0 has no pause -- its
# only signal feature is `--history`, a SIGUSR1 replay buffer -- and
# SIGSTOP/SIGCONT is not a stand-in: frame timestamps come from the compositor
# clock, so a stopped-then-continued recorder emits one enormous frozen frame
# and wrecks the timing, while its Wayland buffers back up for as long as it is
# not reading. So pause finalizes the current segment and resume starts a new
# one with byte-identical capture parameters -- same output or geometry, same
# encoder, same streams -- which is what lets stop join them with ffmpeg's
# concat demuxer. The video is stream-copied and never re-encoded; the audio
# has to be, for a reason specific to AAC that concat_segments() sets out. A
# recording that was never paused is a single segment that is simply renamed
# into place, and is not re-encoded at all.
#
# Audio is the microphone and the system output together, so a recorded call
# carries both halves of the conversation. wl-screenrec accepts only one
# capture device, so the mixing happens in PipeWire, in the null sink declared
# by modules/hardware/audio.nix; this script only names its monitor. See
# mix_available() below for why the naming is not blindly trusted.
#
# Exactly one invocation runs at a time. Every action here is a
# read-modify-write of a session that lives on disk, and stop() in particular
# spends minutes joining files that a second invocation would happily throw
# away underneath it. The flock at the bottom of this file serializes the lot;
# the comment there records the 63-minute recording that was lost proving it
# necessary.

set -euo pipefail

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
# Line-based `key=value`; see write_state(). Empty means idle.
state_file="$runtime_dir/screen-record.state"
log_file="$runtime_dir/screen-record.log"
concat_list="$runtime_dir/screen-record.concat"
# Held for the lifetime of every invocation; see the acquisition at the bottom.
# A file of its own rather than the state file, which write_state() replaces by
# rename: the lock lives on the open file description, so locking a path that is
# unlinked out from under it would leave two invocations holding locks on two
# different inodes and believing they were alone.
lock_file="$runtime_dir/screen-record.lock"
rec_dir="${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings"

# Encoding settings. Sessions here run 40-60 minutes and should land in the
# same ballpark as a Zoom or Teams meeting recording, roughly 300 MB - 1 GB an
# hour.
#
# -b is BYTES per second, and it is not the output bitrate. That gap is why an
# earlier 200 kB setting rendered 11px UI text as mush. wl-screenrec sets only
# AVCodecContext.bit_rate -- no maxrate, no bufsize, no CRF -- and VA-API's VBR
# controller turns that into a per-frame budget of bit_rate/nominal_fps, where
# nominal_fps is the *display refresh*: wl-screenrec passes the monitor's mode,
# never --max-fps. Damage tracking then submits a frame only when the screen
# changed, so a mostly-static session codes a small fraction of the nominal
# frames and spends the same fraction of the budget. Measured against a
# losslessly-rendered Outlook-web clip, ~26% of whose frames change:
#
#   -b  200 kB  1920x1080@60   50 MB/hour   preview lines unreadable
#   -b 1500 kB  1920x1080@60  265 MB/hour   indistinguishable from the source
#   -b 1500 kB  2200x1650@40  512 MB/hour   indistinguishable from the source
#   audio 16 kB/s = 128 kbps   58 MB/hour   (wl-screenrec's own default)
#
# So 1500 kB is ~320 MB/hour on the laptop and ~570 MB/hour on the desktop,
# both inside the band. The band is not a guarantee: a screen that changes on
# every captured frame codes max_fps/refresh of the nominal frames and would
# reach ~1.4 GB/hour at 60 Hz and ~2 GB/hour at 40 Hz. Full-screen video does
# that; a call or a document does not.
#
# The unit suffix is mandatory rather than decoration: the parser rejects a
# bare `1500000` with "no multiple".
#
# The codec stays at wl-screenrec's default (AVC/H.264), deliberately. HEVC is
# not the usual free 30-50% here, because the two machines disagree: at 1500 kB
# it beats AVC by a wide margin on the laptop's Intel iGPU (185 MB/hour at
# 55.7 dB XPSNR-Y against 265 MB/hour at 46.0) and is consistently worse on the
# desktop's AMD radeonsi (597 MB/hour at 36.3 dB against 512 at 37.7). One
# constant serves both hosts, so the codec that is good enough on both -- and
# that every browser and player can open, which matters for sharing these --
# takes it.
#
# --max-fps is a size knob, not a quality knob, and is not what broke the text.
# The per-frame budget is fixed by the refresh rate, so halving the cap halves
# the file and leaves per-frame quality where it was: at 2200x1650, cap 15 gave
# 169 MB/hour at 27.5 dB and cap 30 gave 264 MB/hour at 27.4 dB for the same
# -b. 15 stays because it is invisible on a screencast and holds the worst case
# down.
video_bitrate="1500 kB"
max_fps=15

# Audio device. wl-screenrec 0.2.0 takes exactly one --audio-device, and a bare
# --audio means the default capture device -- normally just the microphone, so
# a recorded call would carry the user's own half of the conversation and none
# of the other participants'. The mix that fixes this is a null sink declared
# in modules/hardware/audio.nix: the default sink's monitor and the default
# source are looped into it, and its monitor is a single device carrying both.
#
# Named, not discovered: the wrapper must not care which speakers or microphone
# are current, and it deliberately does not, because the two loopbacks follow
# the default devices themselves.
mix_sink="screen-record-mix"
mix_device="$mix_sink.monitor"

# True when the mix sink is present in the PipeWire graph.
#
# This has to be an explicit check, because wl-screenrec does not fail on a
# missing --audio-device: measured against a name that does not exist, it runs
# happily for as long as you let it and writes a fully silent AAC track, with
# nothing in its output to say so. So the degradation ladder below can never
# learn about a missing mix by watching the recorder die -- it has to ask.
#
# ~10ms, which is why start() does not call this. See supervise().
mix_available() {
  local nodes
  # Non-zero when pw-cli is missing or cannot reach PipeWire at all, which is
  # the same answer as "the mix is not there" and is treated as such.
  nodes="$(pw-cli ls Node 2> /dev/null)" || return 1
  case "$nodes" in
    *"node.name = \"$mix_sink\""*) return 0 ;;
  esac
  return 1
}

# Every notification carries the same synchronous hint, so mako replaces the
# previous one in place instead of stacking a column of them. That is what
# makes the optimistic-then-correct pattern in supervise() safe: a correction
# overwrites the message it is correcting.
#
# Two flavours, and what separates them is how long each stays on screen.
# Hyprland applies `no_screen_share` to mako's layer, which does not omit
# notifications from a recording -- it paints an opaque black rectangle over
# mako's box in the captured frame, for exactly as long as the notification is
# up. Every notification this script sends is therefore a visible artifact in
# the recording it is narrating, and its timeout is the size of that artifact.
#
# So routine status is terse and brief: 2 seconds and a summary with no body at
# all, which mako's `[body=""]` rule collapses to a single bold line.
#
# The leading glyph is the icon, and that is not a workaround. It is what the
# dictation notifications do -- `● Recording…`, `⏸ Paused`, `✓ Inserted`, all
# title-only, all passing no `-i` at all -- because mako sets `icons=0` in dark
# mode and drops a real icon on the floor. Matching the dictation set means
# matching that, glyphs included, so the two read as one system. Nothing here
# reminds the user of a keybind; they just pressed it.
notify() {
  notify_timed 2000 "$1"
}

# The same title-only status with a lifetime the caller picks, for the two
# places where 2 seconds is the wrong length.
#
# stop() announces a join and then blocks in ffmpeg. Since the join re-encodes
# the audio it runs for minutes on a long session, so a 2-second toast is gone
# almost immediately and the screen goes back to looking exactly like nothing
# happened -- which is what made the user press stop again and cost them most of
# a recording. The announcement therefore has to outlive the operation it is
# announcing, and the completion line has to still be there when the user looks
# back after several minutes away.
#
# Long timeouts are safe here specifically because they are not left to expire:
# every exit path out of the join sends a replacement carrying the same
# synchronous hint, so mako overwrites the progress message in place the moment
# there is a verdict. The bound is the backstop for a script that is killed
# mid-join, not the normal way these end.
notify_timed() {
  notify-send -t "$1" \
    -h string:x-canonical-private-synchronous:screen-record "$2"
}

# The exception. A failure usually means files were left on disk waiting on a
# decision, and 2 seconds is not long enough to read that, so alerts keep a body
# and stay up 15 seconds. They still expire, and deliberately: a notification
# that never timed out would be a permanent black rectangle in every recording
# made after it.
notify_alert() {
  notify-send -t 15000 \
    -h string:x-canonical-private-synchronous:screen-record "⚠ Screen recording" "$1"
}

# "screen" -> "Screen", for the notification summaries.
mode_label() {
  case "$1" in
    region) printf 'Region' ;;
    *) printf 'Screen' ;;
  esac
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
# st_mix    1 while --audio-device names the mic+system mix, 0 for the plain
#           default capture device. Only meaningful while st_audio=1.
# st_pid    the live recorder, meaningful only while st_state=recording
# st_args   capture arguments, replayed verbatim on every resume
# st_segs   the segment files, in order; the last one is the current segment
# st_short  the live-segment count a stop() has already reported as short of
#           st_segs, and empty when it has not. This is the whole of the
#           confirmation stop() asks for before joining an incomplete session --
#           see the count check there for why the warning is a state transition
#           rather than a prompt.
#
# st_hw, st_audio and st_mix are part of the session, not of one launch: every
# segment must be produced by the same encoder with the same set of streams, or
# the `-c:v copy` join in stop() has nothing valid to write.
st_state=""
st_target=""
st_mode=""
st_hw=""
st_audio=""
st_mix=""
st_pid=""
st_short=""
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
    printf 'mix=%s\n' "$st_mix"
    if [ -n "$st_pid" ]; then
      printf 'pid=%s\n' "$st_pid"
    fi
    # Absent until a stop() has warned about missing segments, so an ordinary
    # session's state file is unchanged by any of this.
    if [ -n "$st_short" ]; then
      printf 'short=%s\n' "$st_short"
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
  st_state=""; st_target=""; st_mode=""; st_hw=""; st_audio=""; st_mix=""
  st_pid=""; st_short=""
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
      mix) st_mix="$value" ;;
      pid) st_pid="$value" ;;
      short) st_short="$value" ;;
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
  # No mix= line means a state file written before the mix existed, whose
  # segments were recorded off the plain default device. Resuming has to match
  # them, so 0 rather than 1 is the safe default here.
  [ -n "$st_mix" ] || st_mix="0"

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
  # `-c:v copy` join in stop().
  local tune=(-b "$video_bitrate" --max-fps "$max_fps")
  if [ "$st_hw" != "1" ]; then
    tune+=(--no-hw)
  fi
  if [ "$st_audio" = "1" ]; then
    # On by default because a narrated 40-60 minute screencast that turns out
    # to be silent is only discovered an hour in.
    tune+=(--audio)
    if [ "$st_mix" = "1" ]; then
      # Microphone and system audio together. Without this it is the default
      # capture device, which is the microphone alone.
      tune+=(--audio-device "$mix_device")
    fi
  fi
  # `env --default-signal=INT` is load-bearing, not decoration. Bash sets
  # SIGINT (and SIGQUIT) to SIG_IGN for a background job in a non-interactive
  # shell and the child inherits it -- measured as SigIgn 0x6 on a plain `cmd
  # &`, 0x4 with this reset. Without it the recorder would start with SIGINT
  # ignored and neither the stop nor the pause path below could ever reach it,
  # so every recording would have to be killed and every file would be a
  # corrupt container.
  # `9>&-` is the other load-bearing redirection, and it is what keeps the lock
  # at the bottom of this file honest. This is the one child that outlives the
  # script -- it records for the next hour while every invocation that started
  # it has long exited -- and bash deliberately does *not* set close-on-exec on
  # a descriptor opened by `exec`, so without this the recorder inherits fd 9.
  # An inherited descriptor shares the open file description the lock lives on,
  # so the flock stays held for as long as *any* holder of that description is
  # alive: measured, a child that inherits it keeps the lock after the parent
  # exits, and every later invocation is refused as busy for the whole
  # recording. Closing it in the child costs nothing -- the recorder has no use
  # for the lock and must never hold it.
  #
  # `env` execs in place, so $! is still the recorder's own PID.
  env --default-signal=INT wl-screenrec \
    ${st_args[@]+"${st_args[@]}"} "${tune[@]}" -f "$out" \
    >> "$log_file" 2>&1 9>&- &
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
  if [ "$st_audio" != "1" ]; then
    if [ "$st_hw" = "1" ]; then
      printf 'no audio, no capture device available'
    else
      printf 'software encoding and no audio'
    fi
  elif [ "$st_hw" != "1" ]; then
    if [ "$st_mix" = "1" ]; then
      printf 'software encoding, no hardware encoder available'
    else
      printf 'software encoding, microphone only'
    fi
  else
    printf 'microphone only, no system-audio mix available'
  fi
}

# SIGINT the recorder we just launched and wait for it to let go of its segment.
#
# Only used by supervise() when it has to relaunch a recorder that is still
# alive, which the degradation ladder never has to do -- a rung that failed
# failed by exiting. Two processes writing one path would interleave two MP4s
# into one unplayable file, so the relaunch waits for the old one to be gone.
relinquish() {
  local i
  kill -INT "$pid" 2> /dev/null || true
  for i in $(seq 1 30); do
    is_recorder "$pid" "${st_segs[-1]}" || return 0
    sleep 0.1
  done
  kill -KILL "$pid" 2> /dev/null || true
  for i in $(seq 1 20); do
    is_recorder "$pid" "${st_segs[-1]}" || return 0
    sleep 0.1
  done
  return 1
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
  local phase="$1" rung hw audio mix mix_ok="$st_mix"
  # Settle the audio device before anything else, for the same reason the
  # notification is optimistic: probing the graph costs ~10ms, and start()
  # spends about 17ms getting from the keypress to the notification, so asking
  # there would have more than doubled it. start() assumes the mix is present
  # -- after a rebuild it always is -- and this corrects the assumption a few
  # frames later if it was wrong, which is cheap because the segment is
  # restarted from the beginning either way.
  #
  # Only at start. A resume must reproduce the earlier segments' streams
  # exactly or stop() cannot join them at all -- the video is stream-copied,
  # and a channel-count change would break even the audio re-encode. So st_mix
  # is replayed
  # from the state file there, even if the mix has appeared or vanished since.
  if [ "$phase" = "start" ]; then
    if mix_available; then
      mix_ok="1"
    else
      mix_ok="0"
    fi
    if [ "$mix_ok" != "$st_mix" ] && state_still_owns "$pid"; then
      log "mix $mix_device availability is $mix_ok, session started with $st_mix; relaunching"
      if relinquish; then
        st_mix="$mix_ok"
        launch "${st_segs[-1]}"
        st_pid="$pid"
        write_state
      else
        log "could not stop $pid to switch audio device; leaving it alone"
      fi
    fi
  fi

  if survived; then
    if [ "$st_hw" = "1" ] && [ "$st_audio" = "1" ] && [ "$st_mix" = "1" ]; then
      return 0
    fi
    # Started, but not on the ideal configuration -- the mix correction above
    # is the only way to get here without the ladder having run, and it is a
    # real loss (no system audio) that the user should hear about now rather
    # than when they play the recording back.
    if [ "$phase" = "start" ]; then
      notify_alert "Recording $st_mode — $(degraded_note)"
    fi
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
    notify_alert "Resume failed — see $log_file. Still paused with $(count_segments) segment(s)."
    exit 1
  fi

  # Degradation ladder, "<hw> <audio> <mix>", best first and starting one rung
  # below the ideal "1 1 1" that start() already tried. Three capabilities can
  # each fail independently, so this drops one at a time rather than all at
  # once, cheapest loss first.
  #
  # The mix goes first: it is the newest thing in the chain and the least
  # costly to lose, since dropping it still records the microphone and so still
  # captures the narration. (A mix that is simply absent was already handled
  # above without spending a rung; this covers one that exists but cannot be
  # opened.) Then the encoder: wl-screenrec defaults to VA-API hardware
  # encoding -- mesa's radeonsi covers the home desktop's amdgpu and
  # intel-media-driver the laptop's Intel iGPU, both via hardware.graphics
  # (modules/hardware/video.nix) -- and dropping to a CPU encode still beats a
  # zero-byte file with no indication anything went wrong. Audio is given up
  # last and only after software encoding has been tried with it, because a
  # silent recording of a narrated session is the more expensive loss.
  for rung in "1 1 0" "0 1 1" "0 1 0" "1 0 0" "0 0 0"; do
    hw="${rung%% *}"
    audio="${rung#* }"
    audio="${audio%% *}"
    mix="${rung##* }"
    # No point spending 2s re-testing a mix the probe above says is not there.
    if [ "$mix" = "1" ] && [ "$mix_ok" != "1" ]; then
      continue
    fi
    if [ "$hw" = "$st_hw" ] && [ "$audio" = "$st_audio" ] && [ "$mix" = "$st_mix" ]; then
      continue
    fi
    st_hw="$hw"
    st_audio="$audio"
    st_mix="$mix"
    launch "${st_segs[-1]}"
    st_pid="$pid"
    write_state
    # Notified only once a rung has actually held, so a ladder walk costs one
    # correction rather than one per attempt.
    if survived; then
      notify_alert "Recording $st_mode — $(degraded_note)"
      return 0
    fi
    if ! state_still_owns "$pid"; then
      return 0
    fi
  done

  clear_state
  notify_alert "Failed to start — see $log_file"
  exit 1
}

start() {
  local mode="$1" output geometry
  mkdir -p "$rec_dir"
  st_mode="$mode"
  st_hw="1"
  st_audio="1"
  # Optimistic, and deliberately not checked here: mix_available() costs ~10ms
  # against a ~17ms keypress-to-notification path. supervise() checks it a few
  # frames later and restarts the segment if this was wrong.
  st_mix="1"
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
  notify "● Recording $(mode_label "$mode")…"
  supervise start
}

pause() {
  if ! finalize_current 100; then
    # A long segment can take a while to write its index. Keep the state so the
    # next trigger retries this pause instead of doing something else.
    notify_alert "Still finalizing the segment — trigger again in a moment"
    exit 0
  fi
  st_state="paused"
  st_pid=""
  write_state
  notify "⏸ Paused"
}

resume() {
  st_segs+=("$(segment_path $((${#st_segs[@]} + 1)))")
  launch "${st_segs[-1]}"
  st_state="recording"
  st_pid="$pid"
  write_state
  notify "● Recording $(mode_label "$st_mode")…"
  # No degradation ladder here, deliberately. Every segment has to share one
  # codec, one pixel format and one set of streams for `-c:v copy` to join
  # them, so switching encoders or dropping the audio track mid-session would
  # produce a set of files that cannot be concatenated. Failing back to paused
  # keeps the earlier segments saveable instead.
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

# Join $@ into $st_target with the concat demuxer: video stream-copied, audio
# re-encoded.
#
# The asymmetry is the point, and each half is what that stream needs rather
# than a compromise between them.
#
# Video is never re-encoded, and that invariant is load-bearing. These are
# 1500 kB/s VA-API H.264 captures (see the encoding settings at the top); a
# re-encode would cost minutes on a 40-60 minute session and spend visible
# quality doing it. `-c:v copy` is legal precisely because every segment came
# out of one recorder launched with byte-identical capture arguments -- same
# output or geometry, same encoder, same pixel format, same streams -- which is
# what launch(), resume() and supervise() go to such lengths to guarantee. That
# reasoning is unchanged.
#
# Audio has to be re-encoded, and `-c copy` here was a bug rather than a missed
# optimization. Each segment is an independently encoded AAC-LC track, so each
# one opens with 1024 samples of encoder priming: the codec's start-up
# transient, which is not program audio. The muxer marks it for the player to
# throw away, as an edit list entry with media_time=1024 on the audio track.
# Concatenating under stream copy collapses those per-file edit lists into a
# single track-level entry with media_time=0, and the mark is gone -- so every
# segment's priming block survives into the output as ordinary audible audio.
# That is a 21.3 ms dropout (1024 samples at 48 kHz) at every single pause,
# 20-40 dB below program level: an audible hole in exactly the place the user
# pressed a key, and so in exactly the place they were most likely to be
# mid-sentence.
#
# Decoding the audio is what fixes it. Run through the concat demuxer, ffmpeg
# propagates each input's per-packet skip_samples side data, so each segment's
# priming is discarded while it is still known about and only real samples
# reach the encoder. Measured on a real 4-segment session: under `-c copy` the
# join decoded to 9,618,432 samples against the segments' own 9,614,336, which
# is 4096 too many -- exactly 4 x 1024, one priming block per segment. Its
# first boundary read -65.0, -64.4, -50.1, -49.1 dBFS across four 1024-sample
# windows, and -19.5, -23.2, -27.0, -25.7 after re-encoding, which is program
# level. All three boundaries came out clean.
#
# The cost is a second AAC generation on a ~128 kbps speech track, which is
# inaudible, and 3.1 s of CPU to rebuild a 3.5-minute file. A 21 ms dropout at
# every pause is not inaudible. 128k is wl-screenrec's own audio bitrate, so
# the track does not change size either.
#
# What this deliberately does not do: ffmpeg writes media_time=0 for its own
# encode too, so the output's first 21 ms is the new encoder's priming, audible
# at the very start of the file. That sits at t=0 rather than at a pause, where
# a screencast has not begun. `-af atrim=start_sample=1024` looks like the
# remedy and was measured not to be: it deletes 1024 samples of real audio,
# whereupon the muxer represents the resulting gap as an empty edit and puts
# 21 ms of silence back in the same place. The head dropout came out unchanged
# (-58.0 dBFS with it against -59.1 without, both spanning the same 1024
# samples) while the whole audio track then ran 21 ms ahead of the video -- an
# audio marker authored in sync with a video flash landed at 1.000 s against
# the flash's 1.021 s. A permanent A/V offset in exchange for nothing.
concat_segments() {
  local s esc
  : > "$concat_list"
  for s in "$@"; do
    # The demuxer's own quoting: a literal ' inside a quoted path is '\''.
    esc="${s//\'/\'\\\'\'}"
    printf "file '%s'\n" "$esc" >> "$concat_list"
  done
  # -safe 0 because the list holds absolute paths. -c:v copy passes the H.264
  # through untouched; -c:a aac -b:a 128k is the re-encode the priming skip
  # above requires. A session recorded without audio has no audio stream for
  # the latter two to apply to, and they are simply ignored.
  ffmpeg -hide_banner -loglevel error -y \
    -f concat -safe 0 -i "$concat_list" \
    -c:v copy -c:a aac -b:a 128k "$st_target" >> "$log_file" 2>&1
}

# Check that a path is one this script wrote and is safe to dispose of, without
# disposing of it. Both disposal routes below go through this, so they cannot
# drift apart on what they are willing to touch.
#
# $path is not free-form input -- start() and resume() wrote it -- but it is
# re-checked here, immediately before the caller acts, so a stale or hand-edited
# state file cannot aim either route at anything else.
#
# 0 validated, 1 there is nothing there, 2 refused (and notified).
validate_discardable() {
  local path="$1" base real
  base="${path##*/}"
  # Rejects an empty path, any directory but the recordings directory, and any
  # `..` component: $base can contain no slash, so a path that still equals
  # "$rec_dir/$base" is a direct child of $rec_dir under that literal name.
  if [ -z "$base" ] || [ "$path" != "$rec_dir/$base" ]; then
    notify_alert "Refusing to discard unexpected path: $path"
    return 2
  fi
  # Covers both shapes this script writes: the final screenrecord_<stamp>.mp4
  # and its screenrecord_<stamp>.partNNN.mp4 segments.
  case "$base" in
    screenrecord_*.mp4) ;;
    *)
      notify_alert "Refusing to discard unexpected file: $base"
      return 2
      ;;
  esac
  if [ -L "$path" ] || [ ! -f "$path" ]; then
    # Never follow a symlink, and a segment that was never written has nothing
    # to throw away.
    return 1
  fi
  # Containment re-checked after resolving. The test above is textual, so a
  # symlinked *parent* -- a swapped-out recordings directory -- would otherwise
  # pass it while pointing somewhere else entirely.
  real="$(realpath -- "$path" 2> /dev/null)" || {
    notify_alert "Refusing to discard unresolvable path: $path"
    return 2
  }
  if [ "$real" != "$(realpath -- "$rec_dir" 2> /dev/null)/$base" ]; then
    notify_alert "Refusing to discard unexpected path: $path"
    return 2
  fi
  return 0
}

# Move one file this script created to the desktop trash.
#
# Deliberately not `rm`: `gio trash` is reversible (`gio trash --restore`), so
# the segment cleanup after a successful join costs a trip to the wastebasket
# rather than the recording. This is the route for segments whose content was
# already saved; cancel() takes the purging route below instead.
#
# 0 trashed, 1 there was nothing to trash, 2 refused or failed.
trash_one() {
  local path="$1" status=0
  validate_discardable "$path" || status=$?
  if [ "$status" != "0" ]; then
    return "$status"
  fi
  if gio trash -- "$path"; then
    return 0
  fi
  notify_alert "Discard failed — $path kept"
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

# The guarded purge, alongside this script. Overridable so the test suite can
# substitute a failing stub; in the Nix build the wrapper sets it.
libexec_dir="${SCREEN_RECORD_LIBEXEC:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"

# Delete the segments named in $@ for real, as cancel() and drop_segment() mean
# it.
#
# A discarded recording is one the user decided is worthless, and at hundreds of
# megabytes to gigabytes a session those must not accumulate in the wastebasket
# the way trash_one() leaves them. Deleting is still not an unlink: the segments
# are renamed into a timestamped batch with a manifest, verified there, and only
# then purged, so the whole operation stays reversible until its last step. See
# discard-segments.py, which re-runs every guard below independently and refuses
# to purge anything it cannot account for.
#
# Takes a list rather than reading st_segs so that dropping a single segment and
# cancelling the whole session are one disposal route with one set of guards,
# instead of two that can drift apart on what they are willing to touch.
#
# Non-zero if any segment was refused or the purge failed; on that path the
# files are still on disk, either in place or in the batch directory. A segment
# that is simply not there is not a failure -- validate_discardable() answers 1
# for it and there is nothing left to delete, which is the outcome the caller
# wanted.
purge_segments() {
  local s rc=0 status
  local -a keep=()
  for s in "$@"; do
    status=0
    validate_discardable "$s" || status=$?
    case "$status" in
      0) keep+=("$s") ;;
      2) rc=1 ;;
    esac
  done
  if [ "$rc" != "0" ]; then
    return 1
  fi
  if [ ${#keep[@]} -eq 0 ]; then
    return 0
  fi
  if python3 "$libexec_dir/discard-segments.py" \
    --root "$rec_dir" --purge -- "${keep[@]}" >> "$log_file" 2>&1; then
    return 0
  fi
  notify_alert "Discard failed — segments kept, see $log_file"
  return 1
}

# Every segment of this session, for cancel().
purge_all_segments() {
  purge_segments ${st_segs[@]+"${st_segs[@]}"}
}

# ---------------------------------------------------------------------------
# Terminal actions
# ---------------------------------------------------------------------------

stop() {
  local segs=() n total
  if [ "$st_state" = "recording" ] && ! finalize_current 100; then
    # Keep the state so the next trigger resumes this stop instead of starting
    # a second, overlapping recording on top of it.
    notify_alert "Still finalizing — trigger again in a moment"
    exit 0
  fi

  mapfile -t segs < <(live_segments)
  n=${#segs[@]}
  total=${#st_segs[@]}

  if [ "$n" -eq 0 ]; then
    # Every segment is absent or zero-byte, so there is nothing here to reduce
    # and nothing the count check below could protect: what trash_all_segments()
    # sweeps up is by definition empty. The session never captured anything, or
    # its files are all gone -- either way there is no recording to save and no
    # decision to put to the user.
    clear_state
    trash_all_segments || true
    notify_alert "Stopped, but nothing was written — see $log_file"
    return 0
  fi

  # Refuse to quietly save less than the session says it has.
  #
  # live_segments() skips a segment that is not there, which is deliberate and
  # is what makes a stillborn resume or a hand-deleted bad take harmless. The
  # defect was that stop() then joined whatever came back without ever comparing
  # it against st_segs, so "76 of the 88 segments still exist" and "this session
  # has 76 segments" were indistinguishable -- and the join is immediately
  # followed by trash_all_segments(), which disposes of the evidence. That is
  # how a 63-minute recording was saved as a 41-minute file reported with a ✓.
  #
  # Refusing outright would be wrong: deleting a spoiled take by hand is
  # supported, and a session that could never be stopped again would be a worse
  # failure than the one being fixed. So the discrepancy is made visible and
  # joining it made deliberate -- the first stop reports and does nothing, a
  # second stop within the same discrepancy goes ahead with the survivors.
  # Nothing is joined and nothing is trashed on this path, so the segments are
  # all still on disk if the number is a surprise and the user wants to look.
  #
  # st_short remembers the count that was reported rather than a bare "warned"
  # flag, so consent is to a specific set of survivors: if more segments go
  # missing between the two presses, the count no longer matches and the user is
  # asked again about the new number.
  if [ "$n" -ne "$total" ] && [ "$st_short" != "$n" ]; then
    # The recorder is gone by now whatever the state file still claims, and
    # this path leaves the session on disk, so record that too rather than
    # leaving a dead pid behind for load_state() to demote later.
    st_state="paused"
    st_pid=""
    st_short="$n"
    write_state
    # Phrased so it reads correctly at every count, which "1 segments are
    # missing" would not; the script's other counted message settles for
    # "segment(s)" and this one is read at a worse moment than that.
    notify_alert "Missing $((total - n)) of $total segments — trigger again to join the remaining $n"
    exit 0
  fi

  if [ "$n" -eq 1 ]; then
    # Never paused, or paused with everything else empty: one rename inside the
    # recordings directory, no concat and no re-read of the data. An unpaused
    # recording therefore keeps its original audio too -- there is no seam to
    # repair, so concat_segments()'s re-encode never touches it. `mv -n` is
    # not the guard here -- it skips silently and still exits 0 -- so the
    # collision is checked outright, even though a per-second timestamp and a
    # recording that takes longer than a second make one all but impossible.
    if [ ! -e "$st_target" ] && [ ! -L "$st_target" ] && mv -- "${segs[0]}" "$st_target"; then
      clear_state
      # Any *other* segment here was empty, or is already gone and was
      # consented to by the count check above, so it is a leftover to clean up.
      # The renamed one is no longer at its old path and is simply skipped.
      trash_all_segments || true
      notify "✓ Saved to $st_target"
      return 0
    fi
    notify_alert "Could not move ${segs[0]} to $st_target — segment kept"
    exit 1
  fi

  # Says how long this will take, and stays up while it does. Both halves are
  # the fix for the same thing: the join re-encodes the audio (see
  # concat_segments()) and so runs for minutes on a long session, and the old
  # 2-second "Joining n segments…" left the user watching a screen with no
  # evidence anything was happening. What they did next was press stop again.
  #
  # Deliberately not a progress bar or a polling daemon: this script is a set of
  # one-shot commands that fire and exit, and ffmpeg's own progress would need a
  # background reader and a notification loop to display. One honest sentence
  # about the duration, held on screen until there is a verdict, is what the
  # missing feedback actually was.
  notify_timed 300000 "⧗ Joining $n segments — this takes minutes for a long recording"
  if ! concat_segments "${segs[@]}"; then
    # Keep both the segments and the state: the recording is not lost, it is
    # just still in pieces, and a second trigger can retry the join.
    notify_alert "Join failed — $n segments kept in $rec_dir, see $log_file"
    exit 1
  fi
  clear_state
  # Longer than the routine 2 seconds, and for the same reason the announcement
  # is: several minutes have passed and the user is not necessarily still
  # watching. The wording is the plain one the rename path uses -- a join is not
  # a different outcome, just a slower one.
  if trash_all_segments; then
    notify_timed 10000 "✓ Saved to $st_target"
  else
    notify_alert "Saved to $st_target — joined $n segments, some could not be cleaned up"
  fi
}

# Take the current segment away from the live recorder, for the two discard
# paths below.
#
# Unlike stop(), no container ever has to end up valid here, so this does not
# wait out a long index flush: SIGINT first, so wl-screenrec still releases the
# encoder tidily, then SIGKILL once a short grace has passed. The
# `env --default-signal=INT` in launch() is what makes that first SIGINT
# deliverable at all.
#
# Non-zero when the recorder is *still* running afterwards, which is the
# caller's cue to keep both the files and the state rather than dispose of a
# file another process still holds open.
release_current() {
  local i
  if ! finalize_current 20; then
    kill -KILL "$st_pid" 2> /dev/null || true
    for i in $(seq 1 20); do
      is_recorder "$st_pid" "${st_segs[-1]}" || break
      sleep 0.1
    done
  fi
  ! is_recorder "$st_pid" "${st_segs[-1]}"
}

# Stop the running recording and throw every segment away.
#
# Silent when it works. The user asked for no notification on a discard, so the
# recording stopping is the whole signal; a refusal or a failure still speaks up
# below, because silence is for the case that worked.
cancel() {
  if [ "$st_state" = "recording" ] && ! release_current; then
    notify_alert "Could not stop the recorder — segments kept"
    exit 1
  fi
  # Cleared before the disposal: the recorder is gone either way, so a refusal
  # below must not leave a wedged session behind. It notifies loudly instead.
  clear_state
  if ! purge_all_segments; then
    exit 1
  fi
}

# Throw away the most recent segment and keep the rest of the session.
#
# The take-back for a spoiled take: the last few minutes are wrong, everything
# before them is fine. It always lands in `paused`, never back in `recording`,
# and that is the point rather than an omission -- the user just walked away
# from what the camera was pointed at, so the natural next act is to re-compose
# and press Super+I, which resumes onto a fresh segment. Auto-restarting a
# recorder here would be recording exactly the thing they abandoned.
#
# Not silent, unlike cancel(): the session is still sitting there paused with
# files on disk, so it has to say what it did and what is left.
drop_segment() {
  local seg index
  if [ "$st_state" = "recording" ]; then
    if ! release_current; then
      notify_alert "Could not stop the recorder — segment kept"
      exit 1
    fi
    # Persisted before the disposal, because it is already true: the recorder is
    # gone. If the purge below is then refused, what is left on disk is an
    # honest paused session that still lists this segment, and the next resume
    # numbers past it rather than reusing a name that is still taken.
    st_state="paused"
    st_pid=""
    write_state
  fi

  seg="${st_segs[-1]}"
  index=${#st_segs[@]}

  if [ "$index" -eq 1 ]; then
    # Nothing would be left to keep, and load_state() rejects a session with no
    # segments, so a session cannot survive this -- it is a full cancel wearing
    # a different name. Cleared only after the purge succeeded, for the same
    # reason the multi-segment path below drops the entry only then: a session
    # that still owns its segment is recoverable, one that has forgotten a file
    # still on disk is not. Announced rather than silent, because the user asked
    # to drop one take and got the whole recording discarded.
    if ! purge_segments "$seg"; then
      exit 1
    fi
    clear_state
    notify "✂ Dropped the only segment — recording cancelled"
    return 0
  fi

  # The entry leaves st_segs only once the file is really gone. segment_path()
  # and resume() both derive the next index from ${#st_segs[@]}, so a successful
  # drop hands partNNN back to the next resume -- which is only safe because
  # nothing is sitting at that path any more. Keeping the entry on a refusal is
  # what stops the reused name from colliding with a file that survived.
  if ! purge_segments "$seg"; then
    exit 1
  fi
  st_segs=("${st_segs[@]:0:$((index - 1))}")
  write_state
  notify "✂ Dropped segment $index — $((index - 1)) kept"
}

# ---------------------------------------------------------------------------

mode="${1:-screen}"
case "$mode" in
  screen | region | stop | cancel | drop-segment) ;;
  *)
    echo "Usage: screen-record {screen|region|stop|cancel|drop-segment}" >&2
    exit 1
    ;;
esac

# One invocation at a time, from here to the end of whatever it is doing.
#
# Every action below reads the session, works on the files it names, and writes
# it back. write_state()'s atomic rename makes a single write indivisible, which
# is a much smaller claim than it looks: it says nothing about the minutes
# between reading st_segs and finishing with the files it listed. Two
# invocations could each pass through that window unaware of the other, and one
# real session is what it cost.
#
# What happened, on 88 segments: the user pressed stop, and stop() began an
# ffmpeg concat. That join used to take seconds, because it was a pure stream
# copy -- but it now re-encodes the audio to strip the per-segment AAC encoder
# priming (see concat_segments()), so on a 63-minute session it takes minutes.
# That change is correct and stays; what it did was stretch the read-modify-write
# window from a race nobody could hit into one anybody could. Its only feedback
# was a single 2-second toast, so from outside it looked like the keypress had
# not registered, and the user pressed stop again -- several times. Each new
# invocation started its own join over the same segments toward the same target.
# Whichever finished first cleared the state and ran trash_all_segments(),
# pulling the segments out from under the joins still reading them: the log
# shows three dying on `Impossible to open ...part029.mp4`, then part060, then
# part080. A later invocation then called live_segments(), which by design skips
# segments that are not there, found only the survivors, joined them, and
# reported `✓ Saved` -- 41.4 minutes presented as a complete recording of a
# 63-minute session.
#
# So the lock is the first of the two fixes and the count check in stop() is the
# second, and they are aimed at different things. The lock stops the invocations
# from colliding; the check in stop() means that if segments are missing for any
# reason at all, the join says so instead of silently producing a shorter file.
# Neither is sufficient alone.
#
# Non-blocking, and a refusal is reported and then dropped. Queuing would be
# actively wrong -- the queued command would run a second stop, or a pause,
# against a session the first one has already finished with -- and the whole
# point is that the second keypress must not do anything. Exit 0 because these
# are Hyprland binds and rofi entries, where a non-zero exit is noise for
# something that is not an error: the user pressed a key twice.
#
# The cost, accepted knowingly: a trigger during the ~2s supervise() window
# after a start, or during a degradation ladder walk, is now refused rather than
# racing. Being told to press again is the better failure.
exec 9>> "$lock_file"
if ! flock -n 9; then
  notify_alert "Still busy with the last trigger — joining a long recording takes minutes"
  exit 0
fi

if load_state; then
  case "$mode" in
    stop) stop ;;
    cancel) cancel ;;
    drop-segment) drop_segment ;;
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
    # Stopping, cancelling or dropping with nothing running is harmless, not an
    # error.
    stop) notify "Nothing to stop — no recording in progress" ;;
    cancel) notify "Nothing to cancel — no recording in progress" ;;
    drop-segment) notify "Nothing to drop — no recording in progress" ;;
    *) start "$mode" ;;
  esac
fi
