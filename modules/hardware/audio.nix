{
  config,
  pkgs,
  lib,
  ...
}:

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
  };

  # Portege X30W-K: NHLT under-reports 2 DMICs instead of 4, leaving the
  # internal mic silent unless SOF is told the real lane count. Opt-in per
  # machine via portable.quirks.dynabookX30wkDmic in local.nix.
  boot.extraModprobeConfig = lib.mkIf config.portable.quirks.dynabookX30wkDmic ''
    options snd_sof_intel_hda_generic dmic_num=4
  '';
}
