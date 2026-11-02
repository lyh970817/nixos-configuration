{ config, pkgs, ... }:

let
  toml = pkgs.formats.toml { };
in
{
  home.packages = [ pkgs.mpv-translate ];

  xdg.configFile."mpv-translate/config.toml".source = toml.generate "mpv-translate.toml" {
    model = {
      # Multilingual, so changing the source language does not need an .en model swap.
      model = "base";
      args = {
        device = "cpu";
        compute_type = "int8";
        cpu_threads = 4;
      };
      task_args = {
        beam_size = 1;
        vad_filter = true;
        word_timestamps = true;
        condition_on_previous_text = false;
      };
    };
    translate = {
      language = "en";
      target_lang = "zh";
      translator = "opus";
      show_original = true;
      show_translation = true;
      gate_model = "";
      lookback_seconds = 3.0;
      seek_chunk_duration = 6.0;
      chunk_duration = 12.0;
      min_chunk_duration = 3.0;
      max_wait = 12.0;
      max_lead = 30.0;
      word_end_padding = 0.4;
      gap_fill_threshold = 0.0;
      last_segment_hold = 0.0;
    };
    mpv = {
      executable = "${config.programs.mpv.finalPackage}/bin/mpv";
      start_mpv = true;
      start_args.force_window = true;
      ipc_socket = "${config.xdg.cacheHome}/mpv-translate.sock";
      toggle_binding = "ctrl+.";
    };
    subtitle = {
      path = "${config.xdg.cacheHome}/mpv-translate/subs";
      only_network = true;
      margin_bottom = 50;
      font_size = 30;
    };
    ocr.enabled = false;
  };

  xdg.desktopEntries.mpv-translate = {
    name = "mpv (English + Chinese)";
    genericName = "Video player with translated subtitles";
    comment = "Translate English audio locally; Ctrl+. toggles captions";
    exec = "${pkgs.mpv-translate}/bin/mpv-translate %f";
    icon = "mpv";
    terminal = false;
    categories = [
      "AudioVideo"
      "Player"
    ];
    mimeType = [
      "video/mp4"
      "video/x-matroska"
      "video/webm"
    ];
  };
}
