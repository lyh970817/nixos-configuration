{
  config,
  pkgs,
  lib,
  ...
}:

let
  # The virtual sink screen-record records from; its Pulse monitor is
  # "${screenRecordMix}.monitor", which is what the wrapper passes to
  # wl-screenrec's --audio-device (pkgs/screen-record/screen-record.sh).
  screenRecordMix = "screen-record-mix";

  # Relative level of the two legs, as linear amplitude.
  #
  # A sink monitor is tapped *before* the sink's volume control, so system
  # audio arrives at whatever level the application produced -- typically
  # mastered near full scale -- and is not turned down when the user turns
  # their speakers down. The microphone arrives at the capture device's own
  # level and is usually much quieter. Left equal, the system leg buries the
  # voice, which is the failure that matters: the narration is the part of a
  # screencast you cannot reconstruct.
  #
  # So attenuate the loud leg rather than boost the quiet one -- a mic boosted
  # above unity clips as soon as the speaker leans in -- and take the -4.4 dB
  # as summing headroom too, since both legs land in one stereo sink. Retune by
  # editing these two numbers; there is deliberately no UI for it.
  micGain = 1.0; # 0.0 dB
  systemGain = 0.6; # -4.4 dB

  # Both legs are the same shape: capture one thing, play it into the mix.
  #
  # Every stream here is passive on BOTH sides, which is what makes the mix
  # cost nothing while nobody is recording. A passive node "should not keep
  # sinks/sources busy" (pipewire-props(7)), so with no non-passive link
  # anywhere in the chain the loopbacks, the mix sink, the microphone and the
  # speakers all sit suspended. The instant wl-screenrec opens the mix monitor
  # its own non-passive link lights the chain up end to end, and everything
  # falls back to suspended when it exits. Measured on linglong: mic and sink
  # device nodes "suspended" with the mix loaded and idle, "running" only while
  # a consumer was attached.
  #
  # That is not a micro-optimisation. A permanently-live capture stream on the
  # default source would hold the microphone open forever, and WirePlumber's
  # bluetooth policy switches a headset from A2DP down to HSP/HFP whenever the
  # bluetooth source node is *running* with a capture stream attached -- so an
  # always-on mic leg would silently wreck the audio quality of any Bluetooth
  # headphones the moment they became the default source.
  mixLeg =
    {
      name,
      description,
      gain,
      captureProps ? { },
    }:
    {
      name = "libpipewire-module-loopback";
      args = {
        "node.description" = description;
        # One common stereo layout for both ends, so a MONO capture device is
        # remixed into both channels instead of landing only in FL and leaving
        # the right channel silent (see CHANNEL HANDLING in
        # libpipewire-module-loopback(7)).
        "audio.position" = [
          "FL"
          "FR"
        ];
        "capture.props" = captureProps // {
          "node.name" = "${name}-capture";
          "node.description" = description;
          # No target.object: the session manager links a target-less stream to
          # the *current* default device, and re-links it when the default
          # changes (WirePlumber's linking.follow-default-target). That is the
          # whole point -- this laptop moves between speakers, HDMI and
          # Bluetooth, and a mix pinned to one device name would record silence
          # after the first switch.
          "node.passive" = true;
          # ... but only as long as WirePlumber does not remember a target for
          # this stream and pin it. Opt out of both halves of restore-stream:
          # the target, so following the default is never overridden, and the
          # props, so the gain below stays the gain below.
          "state.restore-target" = "false";
          "state.restore-props" = "false";
        };
        "playback.props" = {
          "node.name" = "${name}-playback";
          "node.description" = description;
          "target.object" = screenRecordMix;
          "node.passive" = true;
          "state.restore-target" = "false";
          "state.restore-props" = "false";
          "node.param.Props" = {
            channelVolumes = [
              gain
              gain
            ];
          };
        };
      };
    };
in

{
  # Disable PulseAudio
  services.pulseaudio.enable = false;

  # Enable rtkit for real-time scheduling
  security.rtkit.enable = true;

  # Enable PipeWire
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;

    # DALI KATCH advertises both AudioSource and AudioSink UUIDs. With the
    # local a2dp_sink (receive-audio-from-remote) role enabled, BlueZ races to
    # configure the speaker->laptop capture stream first and the playback
    # connect then fails with EBUSY, so no audio sink ever appears. Keep only
    # a2dp_source (laptop sends audio) for A2DP; this drops the rarely-used
    # ability to use this machine as a Bluetooth speaker for a phone.
    wireplumber.extraConfig."50-bluez-no-a2dp-sink-role" = {
      "monitor.bluez.properties" = {
        "bluez5.roles" = [
          "a2dp_source"
          "bap_sink"
          "bap_source"
          "hfp_hf"
          "hfp_ag"
        ];
      };
    };

    # A recording of a call has to carry both halves of the conversation: the
    # user's own voice from the microphone, and the other participants' voices,
    # which arrive as ordinary playback and are therefore only capturable off
    # the output sink's monitor. wl-screenrec 0.2.0 takes a single
    # --audio-device, so the two have to be one device before it sees them:
    # a null sink that both legs play into, recorded through its monitor.
    #
    # Not role-gated: both machines have a microphone and speakers, and the mix
    # is inert until something records it.
    extraConfig.pipewire."60-screen-record-mix" = {
      "context.objects" = [
        {
          factory = "adapter";
          args = {
            "factory.name" = "support.null-audio-sink";
            "node.name" = screenRecordMix;
            "node.description" = "Screen recording mix (microphone + system audio)";
            "media.class" = "Audio/Sink";
            "audio.position" = [
              "FL"
              "FR"
            ];
            # Never become the default sink. WirePlumber ranks default-device
            # candidates by priority.session and real ALSA sinks score in the
            # hundreds, so 0 loses to every one of them; if it ever won, the
            # user's playback would vanish into the recording mix and be
            # discovered mid-meeting. It can never be picked as the default
            # *source*: WirePlumber refuses Audio/Sink nodes for that outright,
            # and the thing recorded here is a monitor, not a source node.
            #
            # The one case 0 does not cover is a machine with no other sink at
            # all, where this would win by being the only candidate -- which
            # needs every real output to disappear, and means the user has
            # nowhere to play audio anyway.
            "priority.session" = 0;
            # Nothing external moves this sink's volume, so the monitor tap
            # (which sits before the volume control) always hands wl-screenrec
            # the level the two legs mixed to.
            "state.restore-props" = "false";
            "object.linger" = true;
          };
        }
      ];

      "context.modules" = [
        (mixLeg {
          name = "screen-record-system";
          description = "Screen recording: system audio";
          gain = systemGain;
          captureProps = {
            # Capture the monitor ports of a *sink* rather than a source. With
            # no target set, WirePlumber resolves that to the default sink.
            "stream.capture.sink" = true;
          };
        })
        (mixLeg {
          name = "screen-record-mic";
          description = "Screen recording: microphone";
          gain = micGain;
        })
      ];
    };
  };

  # Portege X30W-K: NHLT under-reports 2 DMICs instead of 4, leaving the
  # internal mic silent unless SOF is told the real lane count. Opt-in per
  # machine via portable.quirks.dynabookX30wkDmic in local.nix.
  boot.extraModprobeConfig = lib.mkIf config.portable.quirks.dynabookX30wkDmic ''
    options snd_sof_intel_hda_generic dmic_num=4
  '';
}
