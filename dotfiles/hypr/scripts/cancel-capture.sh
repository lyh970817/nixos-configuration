#!/usr/bin/env bash

# Cancel whatever capture is running -- dictation, a screen recording, or both
# at once -- at the granularity the caller asks for.
#
#   cancel-capture.sh segment  (Super+Escape)        drop the last take
#   cancel-capture.sh all      (Super+Shift+Escape)  discard the recording
#
# Both keys act on *both* subsystems; what separates them is how much of the
# screen recording they throw away. This is the second arrangement of these two
# keys. The first split them by subsystem -- Super+Escape for dictation,
# Super+Shift+Escape for a recording -- which was ambiguous at the moment it
# mattered, because both are usually running at once and the key you pressed
# decided which one you meant. They were then merged into one key that cancelled
# everything, and that history is what this file used to explain; it is
# superseded. The split now is by granularity, which is a property of the act
# rather than of the target, so neither key has to be aimed. Dictation has no
# fragments to drop, so it is cancelled whole either way, and its behaviour is
# unchanged from the merged key.
#
# What the dispatcher is for is the case where nothing is running, which must
# produce one harmless notification rather than one refusal per subsystem, and
# that is why each side is tested before it is invoked instead of being fired
# blindly.
#
# The two cancels are not symmetrical in what they leave behind, which is worth
# knowing before pressing a key that can fire both:
#
#   dictation - destroys nothing. `hyprwhspr-longform cancel` finalizes the
#               long-form transcript and archives it under
#               ~/.local/share/hyprwhspr/longform/raw/ with a _canceled suffix,
#               skipping only the polish and the paste; short dictation has no
#               file to dispose of. Nothing here is deleted or trashed, and it
#               announces itself.
#   recording - deletes. `screen-record cancel` moves every segment to a
#               verified trash batch and then purges it, because a discarded
#               recording is hundreds of megabytes to gigabytes and the user
#               does not want those accumulating in the wastebasket. It says
#               nothing when it works, by request: the recording stopping is
#               the signal. `screen-record drop-segment` deletes the last
#               segment the same way but does announce itself, because the
#               session is still sitting there paused and nothing else would
#               tell the user what is left. Either one still speaks up on a
#               refusal or a failure.
#
# The screen recording is handled first, and deliberately: a long-form dictation
# cancel posts to the recorder and can block for as long as the transcription
# takes, and the recorder must not sit there holding an encoder open behind it.

set -euo pipefail

# Explicit rather than positional-with-a-default: this script is spelled out in
# both binds, and an unrecognised argument must not silently become the
# destructive one.
granularity="${1:-all}"
case "$granularity" in
  segment | all) ;;
  *)
    echo "Usage: cancel-capture.sh {segment|all}" >&2
    exit 1
    ;;
esac

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
whspr_dir="$runtime_dir/hyprwhspr"
# Existence check only -- pkgs/screen-record/screen-record.sh owns this file and
# its format, and gates on the same "non-empty means a session exists" test in
# load_state(). Asking here is what lets the idle case answer for both
# subsystems at once instead of refusing twice, and a wrong guess costs nothing:
# screen-record re-decides authoritatively when it runs.
record_state="$runtime_dir/screen-record.state"

# Title-only and brief, matching the dictation and screen-record notifications:
# mako's `[body=""]` rule renders a bodiless summary as one bold line, and 2
# seconds keeps it from sitting in a recording that is still running -- mako's
# layer is `no_screen_share`, which paints its box black in the captured frame
# rather than omitting it.
notify() {
  command -v notify-send > /dev/null || return 0
  notify-send -t 2000 \
    -h string:x-canonical-private-synchronous:cancel-capture "$1" || true
}

# The two files scripts/hyprwhispr-record consults for the same question.
# hyprwhspr.service's ExecStartPre deletes recording_status on every (re)start,
# so it cannot survive a daemon restart as a stale `true`.
short_dictation_active() {
  local status_file="$whspr_dir/recording_status"
  local visualizer_file="$whspr_dir/visualizer_state"
  [[ -r $status_file && $(< "$status_file") == true ]] && return 0
  [[ -r $visualizer_file && $(< "$visualizer_file") == recording ]] && return 0
  return 1
}

# `hyprwhspr-longform status` is the sanctioned read-only view of the long-form
# recorder, so the port and the endpoint stay in home/programs/hyprwhspr.nix. It
# prints json.dumps(..., indent=2) and always carries a `recording` key, in both
# its service-inactive and service-ready branches.
#
# Anything unreadable counts as active rather than idle. Being wrong that way
# just runs a cancel that finds nothing to cancel; being wrong the other way
# would silently swallow the keypress while a dictation was running.
longform_dictation_active() {
  local out
  command -v hyprwhspr-longform > /dev/null || return 1
  out=$(timeout 6 hyprwhspr-longform status 2> /dev/null) || return 0
  case "$out" in
    *'"recording": false'*) return 1 ;;
    *) return 0 ;;
  esac
}

dictation_active() {
  # Ordered by cost: the short-dictation test is a file read, while the
  # long-form one spends about a second probing when the recorder is down.
  short_dictation_active && return 0
  longform_dictation_active && return 0
  return 1
}

recording_active() {
  [[ -s $record_state ]]
}

cancel_dictation=0
cancel_recording=0
dictation_active && cancel_dictation=1
recording_active && cancel_recording=1

if ((cancel_dictation == 0 && cancel_recording == 0)); then
  notify "Nothing to cancel"
  exit 0
fi

rc=0

if ((cancel_recording == 1)); then
  # The whole recording, or only its last segment. `cancel` is silent when it
  # succeeds, by request -- the recording stopping is the signal -- while
  # `drop-segment` reports what it dropped and what is left. Both speak up if
  # they refuse or fail.
  if [[ $granularity == segment ]]; then
    screen-record drop-segment || rc=$?
  else
    screen-record cancel || rc=$?
  fi
fi

if ((cancel_dictation == 1)); then
  # Routes between long-form and short dictation itself, and announces which.
  hyprwhspr-longform cancel || rc=$?
fi

exit "$rc"
