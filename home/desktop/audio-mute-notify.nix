# Notify on every mute/unmute of the default audio output and microphone, and
# refresh the greeting's audio cache at the same moment.
#
# The mute keybinds are deliberately not hooked: muting from pavucontrol, an
# application, or a headset button has to notify too. Subscribing to the sound
# server covers every path with one implementation.
{ pkgs, ... }:

let
  audioMuteNotify = pkgs.writeShellApplication {
    name = "audio-mute-notify";
    runtimeInputs = with pkgs; [
      coreutils
      libnotify
      pulseaudio
      systemd
      wireplumber
    ];
    text = ''
      # pactl subscribe over pw-mon: both see the same events, but pactl emits
      # one short line per event and nothing at all while idle, where pw-mon
      # dumps ~74 KB per change and ~1.6 KB/s at rest — a stream that would have
      # to be parsed to be ignored. pipewire-pulse is enabled here
      # (modules/hardware/audio.nix), and pkgs.pulseaudio is already pulled in
      # for its CLI alone by home/programs/hyprwhspr.nix.
      #
      # The event says only that something about a sink or source changed;
      # volume moves emit the same line as a mute. So the events are used purely
      # as a wake-up and the mute state is read back from wpctl, with a
      # notification sent only when it actually flipped. State is tracked for
      # the default endpoints rather than per device, so making a muted device
      # the default announces a mute — which is what the user just became
      # subject to, even though nobody pressed a mute key.
      last_sink=""
      last_source=""

      # muted / unmuted, or empty when the server cannot be reached — an
      # unreadable state must not be mistaken for a transition.
      mute_state() {
        local volume
        if ! volume=$(timeout 1s wpctl get-volume "$1" 2>/dev/null); then
          return 0
        fi
        if [[ "$volume" == *"[MUTED]"* ]]; then
          printf 'muted\n'
        else
          printf 'unmuted\n'
        fi
      }

      # Notify first, then hand the ~350ms cache refresh to systemd with
      # --no-block so it cannot delay the popup.
      announce() {
        local label="$1" key="$2" state="$3"
        notify-send -h "string:x-canonical-private-synchronous:$key" \
          "$label" "$state" || true
        systemctl --user start --no-block fastfetch-status-refresh-audio.service \
          || true
      }

      evaluate() {
        local state
        state=$(mute_state '@DEFAULT_AUDIO_SINK@')
        if [[ -n "$state" && "$state" != "$last_sink" ]]; then
          if [[ -n "$last_sink" ]]; then
            announce "Audio output" audio-mute-sink "$state"
          fi
          last_sink="$state"
        fi

        state=$(mute_state '@DEFAULT_AUDIO_SOURCE@')
        if [[ -n "$state" && "$state" != "$last_source" ]]; then
          if [[ -n "$last_source" ]]; then
            announce "Microphone" audio-mute-source "$state"
          fi
          last_source="$state"
        fi
      }

      # Adopt the state present at startup silently; only later flips are news.
      evaluate

      # Process substitution, not a pipeline, so the loop keeps its state.
      while IFS= read -r event; do
        case "$event" in
          *"on sink #"* | *"on source #"*) ;;
          *) continue ;;
        esac
        # A volume drag emits a flood of identical lines. Read the state once
        # the burst has been quiet for 200ms; the drain also swallows the events
        # our own wpctl clients provoke.
        while read -r -t 0.2 _; do :; done
        evaluate
      done < <(pactl subscribe)
    '';
  };
in
{
  # Both machines have audio and a notification daemon, so this is unrelated to
  # portable.role. The mic-mute hotkey is dynabook-only
  # (modules/hardware/dynabook-hotkeys.nix), but nothing here depends on it.
  home.packages = [ audioMuteNotify ];

  systemd.user.services.audio-mute-notify = {
    Unit = {
      Description = "Notify on audio output and microphone mute changes";
      # Dies with the session, like the greeting caches it refreshes: it needs
      # the session's notification daemon, and a stale mute state carried across
      # a login would announce a transition that never happened.
      PartOf = [ "graphical-session.target" ];
      After = [
        "graphical-session.target"
        "pipewire-pulse.service"
        "wireplumber.service"
      ];
      Wants = [
        "pipewire-pulse.service"
        "wireplumber.service"
      ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${audioMuteNotify}/bin/audio-mute-notify";
      # pactl exits when pipewire-pulse restarts; come back and re-adopt state.
      Restart = "always";
      RestartSec = "2s";
      StandardOutput = "journal";
      StandardError = "journal";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
