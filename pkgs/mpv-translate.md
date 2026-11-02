# mpv-translate on these machines

Run `mpv-translate /path/to/video.mkv`, or choose **mpv (English + Chinese)**
from a video's **Open With** menu. Running `mpv-translate` without a file opens
an idle player after model loading; drag a local video into that window.
Ordinary `mpv` playback does not start translation. This setup launches its own
player rather than attaching to an existing player. Use one translated player
at a time on each machine (its IPC socket is `~/.cache/mpv-translate.sock`).

Inside that player, **Ctrl+.** turns translation off/on, **Space** pauses, and
**q** closes the session. Caption models remain in memory while translation is
toggled off. To release them, close the translated player. LiveCaptions remains
a separate application for system audio.

The initial setup uses multilingual Whisper **base** on CPU/int8 (four threads)
and **Helsinki-NLP/opus-mt-en-zh** for English-to-Chinese translation. OCR and
the additional Whisper speech-gate model are disabled. Before first playback,
run `mpv-translate-models` once on each machine to download the configured models
into the normal Hugging Face cache (`~/.cache/huggingface`); later playback reuses
them. The upstream recognizer requires an existing cache and does not download
its model automatically. Allow roughly 500 MB for both models and several GB of
RAM for the Python/PyTorch runtime and inference. Models are mutable user data,
not part of the Nix store. Model loading finishes before the player opens.

PyAV independently reads upcoming audio from the media file. The player waits
up to 12 seconds for initial subtitles on load/forward seek, then resumes when
the first result is ready or the timeout expires. This is an initial wait, not
a continuous guarantee: slow recognition can still fall behind. Processing
throttles when its next chunk is over 30 seconds ahead of playback. English and
Chinese cues use the same media timestamps. Generated bilingual SRT files go to
`~/.cache/mpv-translate/subs`; no subtitle is written beside the original video.
Different files sharing a basename share the upstream subtitle-cache filename.

The managed settings live in `home/programs/mpv-translate.nix`, which generates
`~/.config/mpv-translate/config.toml`. Change `translate.language` for a different
spoken source language, then commit and rebuild both hosts. Whisper base is
multilingual, but OPUS requires an available **direct** Helsinki-NLP language
pair for that source and target; Whisper's language coverage alone does not
establish translation-pair support. Keep the source explicit: this upstream
version's auto-detection path does not reliably select text translation on the
first chunk. The OPUS Chinese model is multilingual and this upstream wrapper
does not select a Chinese variant with a target-language token, so output script
and translation quality need checking on representative material.

For diagnosis, run `mpv-translate --loglevel DEBUG /path/to/video.mkv`. For an
offline subtitle-generation pilot, `mpv-translate-direct /path/to/video.mkv
--language en` runs the same recognizer/translator without a player and writes
the SRT cache. Upstream's `--echo` flag currently does not print the emitted
segment lists, so inspect the SRT itself.
Use accessible local media first. Browser authentication, DRM, Blu-ray playlists,
and every URL supported by mpv are not necessarily accessible to PyAV's separate
decoder.

The pinned code is dayo6/mpv-translate commit
`31dbbf60acd23f182fbc87c56b84f401de14418a`. That repository currently returns
404; the exact commit is retrieved from its surviving alexkoay/mpv-whisper fork
network. No upstream Python source is patched. Its wheel excludes bundled TOML,
allowing the managed user config to be read. Upstream reads the first config it
finds, despite its README describing merging: a working-directory file named
`mpv-translate.toml` takes precedence over the user config.
