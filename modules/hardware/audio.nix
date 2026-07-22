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
  };

  # Portege X30W-K: NHLT under-reports 2 DMICs instead of 4, leaving the
  # internal mic silent unless SOF is told the real lane count. Opt-in per
  # machine via portable.quirks.dynabookX30wkDmic in local.nix.
  boot.extraModprobeConfig = lib.mkIf config.portable.quirks.dynabookX30wkDmic ''
    options snd_sof_intel_hda_generic dmic_num=4
  '';
}
