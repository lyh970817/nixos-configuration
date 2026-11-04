{ config, pkgs, ... }:

let
  toml = pkgs.formats.toml { };

  # One player per profile: separate sockets, and separate subtitle caches
  # because upstream names cached SRTs by video basename alone.
  profile =
    {
      suffix,
      whisper,
      translate,
    }:
    toml.generate "mpv-translate${suffix}.toml" {
      model = {
        model = whisper;
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
      translate = translate // {
        target_lang = "zh";
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
        ipc_socket = "${config.xdg.cacheHome}/mpv-translate${suffix}.sock";
        toggle_binding = "ctrl+.";
      };
      subtitle = {
        path = "${config.xdg.cacheHome}/mpv-translate/subs${suffix}";
        only_network = true;
        margin_bottom = 50;
        font_size = 30;
      };
      ocr.enabled = false;
    };

  launcher =
    {
      command,
      name,
      comment,
    }:
    {
      inherit name comment;
      genericName = "Video player with translated subtitles";
      exec = "${pkgs.mpv-translate}/bin/${command} %f";
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
in
{
  home.packages = [ pkgs.mpv-translate ];

  xdg.configFile."mpv-translate/config.toml".source = profile {
    suffix = "";
    # Multilingual, so changing the source language does not need an .en model swap.
    whisper = "base";
    translate = {
      language = "en";
      translator = "opus";
    };
  };

  # No direct OPUS ja→zh model exists, so Japanese goes through NLLB
  # (distilled 600M, selected in pkgs/mpv-translate-entry.py). Base Whisper
  # recognizes Japanese poorly; small is the lightest usable model.
  xdg.configFile."mpv-translate/ja.toml".source = profile {
    suffix = "-ja";
    whisper = "small";
    translate = {
      language = "ja";
      translator = "nllb";
    };
  };

  xdg.desktopEntries.mpv-translate = launcher {
    command = "mpv-translate";
    name = "mpv (English + Chinese)";
    comment = "Translate English audio locally; Ctrl+. toggles captions";
  };

  xdg.desktopEntries.mpv-translate-ja = launcher {
    command = "mpv-translate-ja";
    name = "mpv (Japanese + Chinese)";
    comment = "Translate Japanese audio locally; Ctrl+. toggles captions";
  };
}
