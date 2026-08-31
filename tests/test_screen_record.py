#!/usr/bin/env python3

"""Behavioural tests for pkgs/screen-record/screen-record.sh.

The real script is run end to end against fake `wl-screenrec`, `notify-send`,
`gio`, `slurp` and `hyprctl` binaries on a private PATH, in a private
XDG_RUNTIME_DIR and XDG_VIDEOS_DIR. The fake recorder is a real ffmpeg encoding
lavfi testsrc in real time, so pausing, resuming and joining exercise actual
MP4 containers through the actual concat demuxer -- ffmpeg itself is not faked.

Nothing here touches the user's ~/Videos, and no test ever runs `rm`: the fake
`gio trash` moves files into a per-test trash directory, exactly as the real one
moves them into the desktop wastebasket, and the whole tree is a
tempfile.TemporaryDirectory.

The cancel path does really delete, through the guarded trash-then-purge in
discard-segments.py -- but only ever inside that temporary tree, and the tests
below check the guards that keep it there as closely as they check the deletion.
"""

import os
import pathlib
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "pkgs" / "screen-record" / "screen-record.sh"
HELPER = ROOT / "pkgs" / "screen-record" / "discard-segments.py"

# The script's own optimistic-notify supervision window (two `sleep 2`s in the
# worst case, plus the recorder launch).
SUPERVISE = 2.0


FAKE_RECORDER = r"""#!/usr/bin/env bash
# Stand-in for wl-screenrec. Reads -f <file> out of its own argv, exactly as the
# real one does, so the script's /proc/<pid>/cmdline identity check works.
set -uo pipefail
file=""
prev=""
for a in "$@"; do
  if [ "$prev" = "-f" ]; then file="$a"; fi
  prev="$a"
done
printf '%s\n' "$*" >> "$FAKE_REC_ARGV_LOG"
printf '%s\n' "$$" >> "$FAKE_REC_PIDS"
case "${FAKE_REC_MODE:-record}" in
  die)
    # An encoder that cannot be opened.
    exit 3
    ;;
  hwfail)
    # No usable VA-API encoder; software encoding works.
    case " $* " in
      *" --no-hw "*) ;;
      *) exit 3 ;;
    esac
    ;;
  audiofail)
    # No usable capture device; video works either way.
    case " $* " in
      *" --audio "*) exit 3 ;;
    esac
    ;;
  mixfail)
    # The mix sink is in the graph but cannot be opened, so only the launches
    # naming it fail. The plain default device still works.
    case " $* " in
      *" --audio-device "*) exit 3 ;;
    esac
    ;;
  hwaudiofail)
    # Both capabilities are unavailable: only the bottom rung starts.
    case " $* " in
      *" --audio "*) exit 3 ;;
    esac
    case " $* " in
      *" --no-hw "*) ;;
      *) exit 3 ;;
    esac
    ;;
  empty)
    # Alive and holding the path in its argv, but never writes a byte.
    : > "$file"
    trap 'exit 0' INT
    sleep 300 &
    wait
    exit 0
    ;;
esac
# `-re` makes this run in real time; without it ffmpeg would encode the whole
# duration instantly and look like a recorder that died on startup.
case " $* " in
  *" --audio "*)
    # A second stream, so the stream-copy join is exercised with the two
    # streams a real --audio recording produces, not just with video.
    exec ffmpeg -hide_banner -loglevel error -y \
      -re -f lavfi -i "testsrc=size=64x48:rate=10" \
      -re -f lavfi -i "sine=frequency=440:sample_rate=48000" -t 300 \
      -c:v mpeg4 -pix_fmt yuv420p -c:a aac "$file"
    ;;
esac
exec ffmpeg -hide_banner -loglevel error -y \
  -re -f lavfi -i "testsrc=size=64x48:rate=10" -t 300 \
  -c:v mpeg4 -pix_fmt yuv420p "$file"
"""

FAKE_NOTIFY = r"""#!/usr/bin/env bash
# Record "<epoch seconds>\t<body>"; the body is notify-send's last argument.
set -uo pipefail
args=("$@")
printf '%s\t%s\n' "$EPOCHREALTIME" "${args[-1]}" >> "$NOTIFY_LOG"
"""

FAKE_GIO = r"""#!/usr/bin/env bash
# Stand-in for `gio trash -- <path>...`: move into a per-test wastebasket.
set -uo pipefail
if [ "${GIO_FAIL:-0}" = "1" ]; then
  exit 1
fi
shift  # the "trash" subcommand
for a in "$@"; do
  if [ "$a" = "--" ]; then continue; fi
  printf '%s\n' "$a" >> "$GIO_LOG"
  mv -- "$a" "$TRASH_DIR/"
done
"""

FAKE_SLURP = r"""#!/usr/bin/env bash
printf '10,20 300x200\n'
"""

FAKE_PW_CLI = r"""#!/usr/bin/env bash
# Stand-in for `pw-cli ls Node`, in the tab-indented `key = "value"` shape the
# real one prints. FAKE_MIX=0 takes the screen-record-mix sink out of the
# graph; FAKE_PW_CLI_FAIL=1 stands in for pw-cli missing or PipeWire being
# unreachable.
set -uo pipefail
printf '%s\t%s\n' "$EPOCHREALTIME" "$*" >> "$PW_CLI_LOG"
if [ "${FAKE_PW_CLI_FAIL:-0}" = "1" ]; then
  exit 1
fi
printf '\tid 38, type PipeWire:Interface:Node/3\n'
printf '\t\tnode.name = "alsa_output.usb-Yichip_USB-Audio-00.analog-stereo"\n'
if [ "${FAKE_MIX:-1}" = "1" ]; then
  printf '\tid 80, type PipeWire:Interface:Node/3\n'
  printf '\t\tnode.name = "screen-record-mix"\n'
fi
"""

FAKE_HYPRCTL_ABSENT = r"""#!/usr/bin/env bash
# Outside a Hyprland session hyprctl exits non-zero; the script must survive it.
exit 1
"""

FAKE_HYPRCTL_MONITORS = r"""#!/usr/bin/env bash
printf '[{"name":"DP-3","focused":true},{"name":"HDMI-A-1","focused":false}]\n'
"""


class ScreenRecordCase(unittest.TestCase):
    hyprctl = FAKE_HYPRCTL_ABSENT

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="screen-record-test-")
        self.root = pathlib.Path(self._tmp.name)
        self.bin = self.root / "bin"
        self.runtime = self.root / "run"
        self.videos = self.root / "videos"
        self.rec_dir = self.videos / "Recordings"
        self.trash = self.root / "trash"
        for d in (self.bin, self.runtime, self.videos, self.trash):
            d.mkdir(parents=True, exist_ok=True)

        self._write_bin("wl-screenrec", FAKE_RECORDER)
        self._write_bin("notify-send", FAKE_NOTIFY)
        self._write_bin("gio", FAKE_GIO)
        self._write_bin("slurp", FAKE_SLURP)
        self._write_bin("hyprctl", self.hyprctl)
        self._write_bin("pw-cli", FAKE_PW_CLI)

        self.notify_log = self.root / "notifications"
        self.gio_log = self.root / "trashed"
        self.argv_log = self.root / "recorder-argv"
        self.pids_file = self.root / "recorder-pids"
        self.pw_cli_log = self.root / "pw-cli-calls"
        for f in (
            self.notify_log,
            self.gio_log,
            self.argv_log,
            self.pids_file,
            self.pw_cli_log,
        ):
            f.touch()

        self.env = dict(os.environ)
        self.env.update(
            PATH=f"{self.bin}:{os.environ['PATH']}",
            XDG_RUNTIME_DIR=str(self.runtime),
            XDG_VIDEOS_DIR=str(self.videos),
            NOTIFY_LOG=str(self.notify_log),
            GIO_LOG=str(self.gio_log),
            TRASH_DIR=str(self.trash),
            FAKE_REC_ARGV_LOG=str(self.argv_log),
            FAKE_REC_PIDS=str(self.pids_file),
            PW_CLI_LOG=str(self.pw_cli_log),
            # The mic+system mix sink is in the graph unless a test removes it.
            FAKE_MIX="1",
            # $EPOCHREALTIME follows the locale's decimal separator.
            LC_ALL="C",
        )
        self.env.pop("FAKE_REC_MODE", None)

    def tearDown(self):
        # Every fake recorder is orphaned by design (the wrapper exits and
        # leaves it running), so reap them explicitly rather than leaking one
        # per test.
        for line in self.pids_file.read_text().splitlines():
            try:
                os.kill(int(line), signal.SIGKILL)
            except (ValueError, ProcessLookupError, PermissionError):
                pass
        self._tmp.cleanup()

    # -- helpers ----------------------------------------------------------

    def _write_bin(self, name, body):
        path = self.bin / name
        path.write_text(body)
        path.chmod(0o755)

    def run_record(self, *args, mode=None, expect=0, **env):
        e = dict(self.env)
        if mode is not None:
            e["FAKE_REC_MODE"] = mode
        e.update({k: str(v) for k, v in env.items()})
        proc = subprocess.run(
            ["bash", str(SCRIPT), *args],
            env=e,
            capture_output=True,
            text=True,
            timeout=120,
        )
        if expect is not None:
            self.assertEqual(
                proc.returncode,
                expect,
                f"args={args} rc={proc.returncode} stderr={proc.stderr}",
            )
        return proc

    def notifications(self):
        out = []
        for line in self.notify_log.read_text().splitlines():
            stamp, _, body = line.partition("\t")
            out.append((float(stamp), body))
        return out

    def bodies(self):
        return [b for _, b in self.notifications()]

    def last_notification(self):
        return self.bodies()[-1]

    def assert_notified(self, needle):
        self.assertTrue(
            any(needle in b for b in self.bodies()),
            f"no notification containing {needle!r} in {self.bodies()}",
        )

    def state(self):
        raw = (self.runtime / "screen-record.state").read_text()
        out = {"arg": [], "seg": []}
        for line in raw.splitlines():
            key, _, value = line.partition("=")
            if key in ("arg", "seg"):
                out[key].append(value)
            elif key:
                out[key] = value
        return out

    def state_is_idle(self):
        path = self.runtime / "screen-record.state"
        return not path.exists() or path.read_text() == ""

    def parts(self):
        return sorted(p.name for p in self.rec_dir.glob("*.part*.mp4"))

    def finals(self):
        return sorted(
            p.name
            for p in self.rec_dir.glob("screenrecord_*.mp4")
            if ".part" not in p.name
        )

    def trashed(self):
        return sorted(p.name for p in self.trash.iterdir())

    def discard_batches(self):
        """Leftover trash batches. A completed purge removes its own."""
        return sorted(p.name for p in self.rec_dir.glob(".discard-*"))

    def launches(self):
        return self.argv_log.read_text().splitlines()

    def pw_cli_calls(self):
        out = []
        for line in self.pw_cli_log.read_text().splitlines():
            stamp, _, args = line.partition("\t")
            out.append((float(stamp), args))
        return out

    def ffprobe(self, path, entries):
        proc = subprocess.run(
            [
                "ffprobe", "-v", "error",
                "-show_entries", entries,
                "-of", "default=nw=1:nk=1", str(path),
            ],
            capture_output=True, text=True, env=self.env,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return proc.stdout.split()

    def record_for(self, seconds, mode=None, capture="screen"):
        """Start a recording and let it capture for a while."""
        self.run_record(capture, mode=mode)
        time.sleep(seconds)

    # -- Part 1: notification latency -------------------------------------

    def test_first_notification_does_not_wait_for_the_survival_check(self):
        started = time.time()
        proc = subprocess.Popen(
            ["bash", str(SCRIPT), "screen"],
            env=self.env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        deadline = started + 10
        first = None
        while time.time() < deadline:
            notes = self.notifications()
            if notes:
                first = notes[0]
                break
            time.sleep(0.01)
        proc.wait(timeout=60)
        self.assertIsNotNone(first, "no notification was ever emitted")
        latency = first[0] - started
        self.assertIn("Recording Screen", first[1])
        # The old code slept 2s before its only notification. Anything under
        # half a second here is dominated by bash startup, not by a wait.
        self.assertLess(latency, 0.5, f"notification took {latency:.2f}s")
        self.run_record("cancel")

    def test_hardware_failure_corrects_the_optimistic_message(self):
        self.run_record("screen", mode="hwfail")
        bodies = self.bodies()
        self.assertIn("Recording Screen", bodies[0])
        self.assertNotIn("software", bodies[0])
        self.assertEqual(
            self.last_notification(),
            "Recording screen — software encoding, no hardware encoder available",
        )
        st = self.state()
        self.assertEqual(st["hw"], "0")
        # Audio is given up last, so it must still be on here.
        self.assertEqual(st["audio"], "1")
        self.assertEqual(st["state"], "recording")
        # The retry reuses the very same segment file.
        self.assertEqual(len(st["seg"]), 1)
        self.run_record("cancel")

    def test_no_capture_device_falls_back_to_a_silent_recording(self):
        self.run_record("screen", mode="audiofail")
        self.assertEqual(
            self.last_notification(),
            "Recording screen — no audio, no capture device available",
        )
        st = self.state()
        self.assertEqual(st["state"], "recording")
        self.assertEqual(st["audio"], "0")
        # Hardware encoding was restored once audio turned out to be the
        # problem, rather than left dropped by the intermediate rung.
        self.assertEqual(st["hw"], "1")
        self.assertNotIn("--no-hw", self.launches()[-1])
        self.assertNotIn("--audio", self.launches()[-1])
        self.run_record("cancel")

    def test_both_capabilities_unavailable_land_on_the_bottom_rung(self):
        self.run_record("screen", mode="hwaudiofail")
        self.assertEqual(
            self.last_notification(),
            "Recording screen — software encoding and no audio",
        )
        st = self.state()
        self.assertEqual(st["state"], "recording")
        self.assertEqual(st["hw"], "0")
        self.assertEqual(st["audio"], "0")
        self.run_record("cancel")

    # -- audio device: the microphone + system-audio mix -------------------

    MIX_DEVICE = "--audio-device screen-record-mix.monitor"
    MIX_LOST = "Recording screen — microphone only, no system-audio mix available"

    def test_audio_device_names_the_mix_when_it_is_in_the_graph(self):
        self.record_for(0.8)
        # Both halves of a call: --audio alone would be the default capture
        # device, which is the microphone on its own.
        self.assertIn(self.MIX_DEVICE, self.launches()[-1])
        self.assertEqual(self.state()["mix"], "1")
        # Nothing was degraded, so the optimistic message is the only one.
        self.assertEqual(self.bodies(), ["● Recording Screen…"])
        self.run_record("cancel")

    def test_the_mix_is_probed_only_after_the_first_notification(self):
        """The probe costs ~10ms and the keypress path is ~17ms, so it must not
        sit in front of the notification."""
        self.run_record("screen")
        first_note = self.notifications()[0][0]
        calls = self.pw_cli_calls()
        self.assertTrue(calls, "the mix was never probed at all")
        self.assertLess(
            first_note,
            calls[0][0],
            f"pw-cli ran at {calls[0][0]} before the notification at {first_note}",
        )
        self.run_record("cancel")

    def test_a_missing_mix_falls_back_to_the_plain_default_device(self):
        self.run_record("screen", FAKE_MIX=0)
        launches = self.launches()
        # Started optimistically on the mix, corrected once the probe answered.
        self.assertIn(self.MIX_DEVICE, launches[0])
        self.assertNotIn("--audio-device", launches[-1])
        self.assertIn("--audio", launches[-1])
        st = self.state()
        self.assertEqual(st["state"], "recording")
        self.assertEqual(st["mix"], "0")
        # Only the device changed: the encoder and the audio track did not.
        self.assertEqual(st["hw"], "1")
        self.assertEqual(st["audio"], "1")
        # The correction reuses the one segment rather than starting a session
        # with a stillborn first part.
        self.assertEqual(len(st["seg"]), 1)
        self.assertEqual(self.last_notification(), self.MIX_LOST)
        self.run_record("cancel")

    def test_a_missing_mix_still_produces_a_playable_recording(self):
        """Graceful degradation is only graceful if the file is still good: the
        relaunch must not leave two recorders writing one segment."""
        self.run_record("screen", FAKE_MIX=0)
        time.sleep(1.5)
        target = self.state()["target"]
        self.run_record("stop")
        self.assertEqual(self.last_notification(), f"✓ Saved to {target}")
        self.assertEqual(self.ffprobe(target, "stream=codec_type"), ["video", "audio"])
        self.assertEqual(self.parts(), [])

    def test_a_mix_that_cannot_be_opened_drops_to_the_default_device(self):
        """The mix is in the graph, so the probe keeps it -- but the recorder
        cannot open it, and the ladder gives it up before the encoder."""
        self.run_record("screen", mode="mixfail")
        st = self.state()
        self.assertEqual(st["state"], "recording")
        self.assertEqual(st["mix"], "0")
        # The mix is the cheapest thing to lose, so nothing else was.
        self.assertEqual(st["hw"], "1")
        self.assertEqual(st["audio"], "1")
        self.assertNotIn("--no-hw", self.launches()[-1])
        self.assertNotIn("--audio-device", self.launches()[-1])
        self.assertIn("--audio", self.launches()[-1])
        self.assertEqual(self.last_notification(), self.MIX_LOST)
        self.run_record("cancel")

    def test_an_unreachable_pw_cli_is_treated_as_no_mix(self):
        self.run_record("screen", FAKE_PW_CLI_FAIL=1)
        self.assertEqual(self.state()["mix"], "0")
        self.assertNotIn("--audio-device", self.launches()[-1])
        self.assertIn("--audio", self.launches()[-1])
        self.run_record("cancel")

    def test_resume_replays_the_sessions_device_even_if_the_mix_vanished(self):
        """Every segment must carry identical streams or stop() cannot join
        them under `-c copy`, so a mid-session change is ignored."""
        self.record_for(0.8)
        self.assertEqual(self.state()["mix"], "1")
        self.run_record("screen")  # pause
        self.run_record("screen", FAKE_MIX=0)  # resume, mix now gone
        time.sleep(0.4)
        launches = self.launches()
        self.assertEqual(len(launches), 2)
        self.assertIn(self.MIX_DEVICE, launches[1])
        self.assertEqual(self.state()["mix"], "1")
        self.run_record("cancel")

    def test_a_session_started_without_the_mix_resumes_without_it(self):
        self.run_record("screen", FAKE_MIX=0)
        time.sleep(0.8)
        self.run_record("screen", FAKE_MIX=0)  # pause
        self.run_record("screen")  # resume, mix back in the graph
        time.sleep(0.4)
        launches = self.launches()
        # launches[0] is the optimistic first try that was corrected away.
        self.assertNotIn("--audio-device", launches[-1])
        self.assertEqual(self.state()["mix"], "0")
        self.run_record("cancel")

    # -- encoding settings -------------------------------------------------

    def test_every_launch_carries_the_same_encoding_settings(self):
        self.record_for(0.8)
        self.assertEqual(self.state()["audio"], "1")
        self.run_record("screen")  # pause
        self.run_record("screen")  # resume
        time.sleep(0.4)
        launches = self.launches()
        self.assertEqual(len(launches), 2)
        for line in launches:
            # Bytes per second, and the unit suffix is mandatory: wl-screenrec
            # 0.2.0 rejects a bare number with "no multiple".
            self.assertIn("-b 200 kB", line)
            self.assertIn("--max-fps 15", line)
            self.assertIn("--audio", line)
            # The capture device is part of "identical parameters" too: two
            # segments recorded off different devices cannot be stream-copied
            # together if their channel counts disagree.
            self.assertIn(self.MIX_DEVICE, line)
        # Identical parameters on every segment is the concat precondition.
        self.assertEqual(launches[0].rsplit(" -f ", 1)[0], launches[1].rsplit(" -f ", 1)[0])
        self.run_record("cancel")

    def test_a_recorder_that_never_starts_reports_failure_and_clears_state(self):
        self.run_record("screen", mode="die", expect=1)
        self.assert_notified("Failed to start")
        self.assertTrue(self.state_is_idle())

    # -- Part 2: pause / resume / stop ------------------------------------

    def test_start_records_a_single_segment_and_pins_the_capture(self):
        self.record_for(0.5)
        st = self.state()
        self.assertEqual(st["state"], "recording")
        self.assertEqual(st["mode"], "screen")
        self.assertEqual(st["hw"], "1")
        self.assertEqual(st["audio"], "1")
        self.assertEqual(st["mix"], "1")
        self.assertEqual(len(st["seg"]), 1)
        self.assertTrue(st["seg"][0].endswith(".part001.mp4"))
        self.assertTrue(st["target"].endswith(".mp4"))
        self.assertNotIn(".part", pathlib.Path(st["target"]).name)
        self.run_record("cancel")

    def test_single_segment_stop_renames_instead_of_joining(self):
        self.record_for(1.0)
        target = self.state()["target"]
        self.run_record("stop")
        self.assertEqual(self.last_notification(), f"✓ Saved to {target}")
        self.assertTrue(pathlib.Path(target).exists())
        self.assertGreater(pathlib.Path(target).stat().st_size, 0)
        self.assertEqual(self.parts(), [])
        # A rename, not a join: nothing was trashed and no concat list was ever
        # handed to ffmpeg.
        self.assertEqual(self.trashed(), [])
        self.assertFalse((self.runtime / "screen-record.concat").exists())
        self.assertTrue(self.state_is_idle())

    def test_pause_then_resume_then_stop_joins_the_segments(self):
        self.record_for(1.0)
        target = self.state()["target"]

        self.run_record("screen")  # pause
        self.assert_notified("⏸ Paused")
        st = self.state()
        self.assertEqual(st["state"], "paused")
        self.assertNotIn("pid", st)
        self.assertEqual(len(st["seg"]), 1)
        first_part = pathlib.Path(st["seg"][0])
        self.assertGreater(first_part.stat().st_size, 0)
        # Nothing is capturing while paused.
        size = first_part.stat().st_size
        time.sleep(0.7)
        self.assertEqual(first_part.stat().st_size, size)

        self.run_record("screen")  # resume
        self.assert_notified("● Recording Screen…")
        st = self.state()
        self.assertEqual(st["state"], "recording")
        self.assertEqual(len(st["seg"]), 2)
        self.assertTrue(st["seg"][1].endswith(".part002.mp4"))
        self.assertEqual(st["target"], target)
        time.sleep(1.0)

        self.assertEqual(len(self.parts()), 2)
        self.run_record("stop")
        self.assert_notified("Joining 2 segments")
        self.assertEqual(self.last_notification(), f"✓ Saved to {target}")
        self.assertTrue(pathlib.Path(target).exists())
        self.assertGreater(pathlib.Path(target).stat().st_size, 0)
        # Both segments went to the wastebasket, not to rm.
        self.assertEqual(len(self.trashed()), 2)
        self.assertEqual(self.parts(), [])
        self.assertTrue(self.state_is_idle())
        # The joined file really is a playable container spanning both parts,
        # and both streams survived the copy -- a two-stream stream-copy concat
        # is the fragile case, so it is asserted rather than assumed.
        self.assertGreater(float(self.ffprobe(target, "format=duration")[0]), 1.0)
        self.assertEqual(
            self.ffprobe(target, "stream=codec_type"), ["video", "audio"]
        )

    def test_three_segments_join_in_order(self):
        self.record_for(0.8)
        for _ in range(2):
            self.run_record("screen")  # pause
            self.run_record("screen")  # resume
            time.sleep(0.8)
        self.assertEqual(len(self.state()["seg"]), 3)
        target = self.state()["target"]
        self.run_record("stop")
        self.assertEqual(self.last_notification(), f"✓ Saved to {target}")
        self.assertTrue(pathlib.Path(target).exists())
        self.assertEqual(len(self.trashed()), 3)

    def test_stop_while_paused_saves_what_exists(self):
        self.record_for(1.0)
        target = self.state()["target"]
        self.run_record("screen")  # pause
        self.assertEqual(self.state()["state"], "paused")
        self.run_record("stop")
        self.assertEqual(self.last_notification(), f"✓ Saved to {target}")
        self.assertTrue(pathlib.Path(target).exists())
        self.assertTrue(self.state_is_idle())

    def test_a_zero_byte_segment_is_skipped_not_concatenated(self):
        self.record_for(1.0)
        target = self.state()["target"]
        self.run_record("screen")  # pause
        # The resumed segment writes nothing at all.
        self.run_record("screen", mode="empty")
        self.assertEqual(len(self.state()["seg"]), 2)
        empty = pathlib.Path(self.state()["seg"][1])
        self.assertTrue(empty.exists())
        self.assertEqual(empty.stat().st_size, 0)

        self.run_record("stop")
        # One live segment left, so the fast path applies and no join is run.
        self.assertEqual(self.last_notification(), f"✓ Saved to {target}")
        self.assertTrue(pathlib.Path(target).exists())
        self.assertGreater(pathlib.Path(target).stat().st_size, 0)
        # The empty leftover was trashed rather than left in the recordings dir.
        self.assertEqual(self.parts(), [])
        self.assertEqual(len(self.trashed()), 1)
        self.assertTrue(self.trashed()[0].endswith(".part002.mp4"))

    def test_every_segment_empty_reports_that_nothing_was_written(self):
        self.record_for(0.5, mode="empty")
        self.run_record("stop")
        self.assert_notified("nothing was written")
        self.assertEqual(self.finals(), [])
        self.assertEqual(self.parts(), [])
        self.assertTrue(self.state_is_idle())

    def test_resume_replays_the_same_capture_parameters(self):
        self.run_record("region")
        time.sleep(0.6)
        st = self.state()
        self.assertEqual(st["mode"], "region")
        self.assertEqual(st["arg"], ["-g", "10,20 300x200"])
        self.run_record("region")  # pause
        self.run_record("region")  # resume
        time.sleep(0.4)
        launches = self.argv_log.read_text().splitlines()
        self.assertEqual(len(launches), 2)
        for line in launches:
            self.assertIn("-g 10,20 300x200", line)
            self.assertNotIn("--no-hw", line)
        self.run_record("cancel")

    def test_a_dead_recorder_becomes_a_paused_session(self):
        self.record_for(1.0)
        st = self.state()
        target = st["target"]
        os.kill(int(st["pid"]), signal.SIGKILL)
        time.sleep(0.3)
        # The next trigger must continue this session rather than open a new one.
        self.run_record("screen")
        st = self.state()
        self.assertEqual(st["target"], target)
        self.assertEqual(st["state"], "recording")
        self.assertEqual(len(st["seg"]), 2)
        self.assert_notified("● Recording Screen…")
        self.run_record("cancel")

    def test_a_resume_that_fails_falls_back_to_paused(self):
        self.record_for(1.0)
        target = self.state()["target"]
        self.run_record("screen")  # pause
        self.run_record("screen", mode="die", expect=1)  # resume, recorder dies
        self.assert_notified("Resume failed")
        st = self.state()
        self.assertEqual(st["state"], "paused")
        self.assertEqual(st["target"], target)
        # The captured segment is still there and still saveable.
        self.run_record("stop")
        self.assertEqual(self.last_notification(), f"✓ Saved to {target}")
        self.assertTrue(pathlib.Path(target).exists())

    # -- cancel ------------------------------------------------------------

    def test_cancel_deletes_every_segment(self):
        """Multi-segment: a paused-and-resumed session is two files, and cancel
        must account for both, not just the current one."""
        self.record_for(0.8)
        self.run_record("screen")  # pause
        self.run_record("screen")  # resume
        time.sleep(0.8)
        segs = [pathlib.Path(s) for s in self.state()["seg"]]
        self.assertEqual(len(segs), 2)
        for seg in segs:
            self.assertTrue(seg.exists())
        before = len(self.bodies())
        self.run_record("cancel")
        # Gone for real, not moved to the wastebasket, and the batch that held
        # them in between was purged along with them.
        for seg in segs:
            self.assertFalse(seg.exists())
        self.assertEqual(self.trashed(), [])
        self.assertEqual(self.discard_batches(), [])
        self.assertEqual(self.parts(), [])
        self.assertEqual(self.finals(), [])
        self.assertTrue(self.state_is_idle())
        # A discard that worked says nothing at all.
        self.assertEqual(len(self.bodies()), before)

    def test_cancel_leaves_the_recordings_directory_empty(self):
        """The purge cleans up after itself: no batch directory, no manifest,
        nothing at all left under the recordings root."""
        self.record_for(0.8)
        self.run_record("cancel")
        self.assertEqual(sorted(p.name for p in self.rec_dir.iterdir()), [])

    def test_cancel_refuses_a_path_outside_the_recordings_directory(self):
        self.record_for(0.8)
        outsider = self.root / "screenrecord_outside.mp4"
        outsider.write_text("precious")
        state_path = self.runtime / "screen-record.state"
        state_path.write_text(state_path.read_text() + f"seg={outsider}\n")
        self.run_record("cancel", expect=1)
        self.assert_notified(f"Refusing to discard unexpected path: {outsider}")
        self.assertTrue(outsider.exists())
        self.assertEqual(outsider.read_text(), "precious")
        # A refusal aborts before anything moves, so the legitimate segment of
        # the same session is still in place too.
        self.assertEqual(len(self.parts()), 1)
        self.assertEqual(self.discard_batches(), [])

    def test_cancel_refuses_an_unexpected_basename(self):
        self.record_for(0.8)
        intruder = self.rec_dir / "notes.txt"
        intruder.write_text("precious")
        state_path = self.runtime / "screen-record.state"
        state_path.write_text(state_path.read_text() + f"seg={intruder}\n")
        self.run_record("cancel", expect=1)
        self.assert_notified("Refusing to discard unexpected file: notes.txt")
        self.assertTrue(intruder.exists())
        self.assertEqual(intruder.read_text(), "precious")
        self.assertEqual(self.discard_batches(), [])

    def test_cancel_never_follows_a_symlink(self):
        self.record_for(0.8)
        secret = self.root / "secret"
        secret.write_text("precious")
        link = self.rec_dir / "screenrecord_link.mp4"
        link.symlink_to(secret)
        state_path = self.runtime / "screen-record.state"
        state_path.write_text(state_path.read_text() + f"seg={link}\n")
        self.run_record("cancel")
        self.assertTrue(secret.exists())
        self.assertEqual(secret.read_text(), "precious")
        self.assertTrue(link.is_symlink())
        self.assertEqual(self.trashed(), [])
        self.assertEqual(self.discard_batches(), [])

    def test_cancel_before_anything_was_written_is_silent(self):
        self.record_for(0.5, mode="empty")
        before = len(self.bodies())
        self.run_record("cancel")
        self.assertTrue(self.state_is_idle())
        self.assertEqual(len(self.bodies()), before)

    def test_a_failing_purge_keeps_the_segments_and_reports_it(self):
        """The purge helper refusing is a failure, and failures are never
        silent -- the segments are still on disk and the user must know."""
        libexec = self.root / "stub-libexec"
        libexec.mkdir()
        (libexec / "discard-segments.py").write_text(
            "import sys\nsys.stderr.write('refused\\n')\nsys.exit(2)\n"
        )
        self.record_for(0.8)
        self.run_record("cancel", expect=1, SCREEN_RECORD_LIBEXEC=str(libexec))
        self.assert_notified("Discard failed")
        self.assertEqual(len(self.parts()), 1)

    def test_a_failing_trash_keeps_the_file_and_reports_it(self):
        """The gio route is still what cleans up after a successful join, and
        it still reports a refusal rather than losing track of the segments."""
        self.record_for(0.8)
        self.run_record("screen")  # pause
        self.run_record("screen")  # resume
        time.sleep(0.8)
        target = self.state()["target"]
        self.run_record("stop", GIO_FAIL=1)
        self.assert_notified("some could not be cleaned up")
        self.assertTrue(pathlib.Path(target).exists())
        self.assertEqual(len(self.parts()), 2)

    # -- idle and malformed state -----------------------------------------

    def test_stop_and_cancel_are_harmless_when_nothing_is_recording(self):
        self.run_record("stop")
        self.assertEqual(self.last_notification(), "Nothing to stop — no recording in progress")
        self.run_record("cancel")
        self.assertEqual(
            self.last_notification(), "Nothing to cancel — no recording in progress"
        )

    def test_a_malformed_state_file_reads_as_idle(self):
        (self.runtime / "screen-record.state").write_text("garbage\nstate=confused\n")
        self.run_record("stop")
        self.assertEqual(self.last_notification(), "Nothing to stop — no recording in progress")
        self.assertTrue(self.state_is_idle())

    def test_an_unknown_mode_is_a_usage_error(self):
        proc = self.run_record("sideways", expect=1)
        self.assertIn("Usage: screen-record", proc.stderr)
        self.assertEqual(self.bodies(), [])


class ScreenRecordFocusedMonitorCase(ScreenRecordCase):
    """The same script with a Hyprland that answers the monitor query."""

    hyprctl = FAKE_HYPRCTL_MONITORS

    # Only the output-pinning behaviour is interesting here; the rest of the
    # suite above already runs against the no-Hyprland fallback.
    def test_the_focused_output_is_pinned_for_every_segment(self):
        self.record_for(0.6)
        self.assertEqual(self.state()["arg"], ["-o", "DP-3"])
        self.run_record("screen")  # pause
        self.run_record("screen")  # resume
        time.sleep(0.3)
        launches = self.argv_log.read_text().splitlines()
        self.assertEqual(len(launches), 2)
        for line in launches:
            self.assertIn("-o DP-3", line)
        self.run_record("cancel")


class DiscardSegmentsGuardCase(unittest.TestCase):
    """The guards in discard-segments.py, exercised directly.

    The wrapper validates before it calls the helper, so in normal operation
    none of these refusals is reachable. They are the second, independent layer:
    this is the only code in the tree that unlinks the user's files, and it has
    to refuse on its own account rather than trusting whatever called it.
    """

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="discard-segments-test-")
        self.root = pathlib.Path(self._tmp.name)
        self.rec_dir = self.root / "Videos" / "Recordings"
        self.rec_dir.mkdir(parents=True)

    def tearDown(self):
        self._tmp.cleanup()

    def segment(self, name, body="video bytes", directory=None):
        path = (directory or self.rec_dir) / name
        path.write_text(body)
        return path

    def discard(self, *paths, root=None, purge=True, expect=0):
        argv = [
            sys.executable,
            str(HELPER),
            "--root",
            str(root if root is not None else self.rec_dir),
        ]
        if purge:
            argv.append("--purge")
        argv += ["--", *(str(p) for p in paths)]
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=60)
        self.assertEqual(
            proc.returncode, expect, f"rc={proc.returncode} stderr={proc.stderr}"
        )
        return proc

    def batches(self):
        return sorted(p.name for p in self.rec_dir.glob(".discard-*"))

    # -- the purge path ----------------------------------------------------

    def test_it_deletes_every_segment_it_was_given(self):
        segs = [
            self.segment("screenrecord_2026-01-01_00-00-00.part001.mp4"),
            self.segment("screenrecord_2026-01-01_00-00-00.part002.mp4"),
            self.segment("screenrecord_2026-01-01_00-00-00.part003.mp4"),
        ]
        self.discard(*segs)
        for seg in segs:
            self.assertFalse(seg.exists())
        # The batch that held them in between is purged too, manifest included.
        self.assertEqual(self.batches(), [])
        self.assertEqual(sorted(p.name for p in self.rec_dir.iterdir()), [])

    def test_it_logs_every_file_it_moved_and_purged(self):
        seg = self.segment("screenrecord_2026-01-01_00-00-00.mp4", body="0123456789")
        out = self.discard(seg).stdout
        self.assertIn("trashed", out)
        self.assertIn("purged", out)
        self.assertIn(str(seg), out)
        self.assertIn("10 bytes", out)

    def test_it_trashes_before_it_purges(self):
        """The ordering is the whole safety property: the file is renamed into
        a manifested batch and verified there before anything is unlinked."""
        seg = self.segment("screenrecord_2026-01-01_00-00-00.mp4")
        out = self.discard(seg).stdout
        self.assertLess(out.index("trashed"), out.index("purged"))

    def test_a_dry_run_deletes_nothing(self):
        seg = self.segment("screenrecord_2026-01-01_00-00-00.mp4")
        out = self.discard(seg, purge=False).stdout
        self.assertIn("would discard", out)
        self.assertTrue(seg.exists())
        self.assertEqual(self.batches(), [])

    def test_a_missing_segment_is_not_an_error(self):
        self.discard(self.rec_dir / "screenrecord_never-written.mp4")
        self.assertEqual(self.batches(), [])

    # -- guard refusals ----------------------------------------------------

    def test_it_refuses_a_path_outside_the_recordings_directory(self):
        outsider = self.segment(
            "screenrecord_2026-01-01_00-00-00.mp4", directory=self.root
        )
        self.discard(outsider, expect=2)
        self.assertTrue(outsider.exists())
        self.assertEqual(self.batches(), [])

    def test_it_refuses_a_traversal_out_of_the_recordings_directory(self):
        outsider = self.segment(
            "screenrecord_2026-01-01_00-00-00.mp4", directory=self.root
        )
        self.discard(self.rec_dir / ".." / outsider.name, expect=2)
        self.assertTrue(outsider.exists())

    def test_it_refuses_an_unexpected_basename(self):
        intruder = self.segment("notes.txt", body="precious")
        self.discard(intruder, expect=2)
        self.assertTrue(intruder.exists())
        self.assertEqual(intruder.read_text(), "precious")

    def test_it_refuses_a_symlink(self):
        secret = self.root / "secret"
        secret.write_text("precious")
        link = self.rec_dir / "screenrecord_2026-01-01_00-00-00.mp4"
        link.symlink_to(secret)
        self.discard(link, expect=2)
        self.assertTrue(link.is_symlink())
        self.assertTrue(secret.exists())
        self.assertEqual(secret.read_text(), "precious")

    def test_it_refuses_a_directory(self):
        directory = self.rec_dir / "screenrecord_2026-01-01_00-00-00.mp4"
        directory.mkdir()
        self.discard(directory, expect=2)
        self.assertTrue(directory.is_dir())

    def test_it_refuses_a_segment_reached_through_a_symlinked_parent(self):
        """Containment is re-checked after resolving, so a recordings directory
        that is really a symlink elsewhere cannot smuggle a path past the
        textual check."""
        elsewhere = self.root / "elsewhere"
        elsewhere.mkdir()
        seg = self.segment("screenrecord_2026-01-01_00-00-00.mp4", directory=elsewhere)
        link_dir = self.root / "Videos" / "Linked"
        link_dir.symlink_to(elsewhere, target_is_directory=True)
        self.discard(link_dir / seg.name, root=self.rec_dir, expect=2)
        self.assertTrue(seg.exists())

    def test_it_refuses_a_root_that_is_not_a_recordings_directory(self):
        seg = self.segment("screenrecord_2026-01-01_00-00-00.mp4")
        self.discard(seg, root=self.rec_dir.parent, expect=2)
        self.assertTrue(seg.exists())

    def test_it_refuses_a_protected_root(self):
        self.discard("/home/nobody/screenrecord_x.mp4", root="/home", expect=2)

    def test_it_refuses_a_shallow_root(self):
        self.discard("/Recordings/screenrecord_x.mp4", root="/Recordings", expect=2)

    def test_a_refusal_anywhere_in_the_batch_stops_the_whole_batch(self):
        """One bad path does not cost the good ones: nothing is moved and
        nothing is purged until every candidate has passed."""
        good = self.segment("screenrecord_2026-01-01_00-00-00.part001.mp4")
        intruder = self.segment("notes.txt", body="precious")
        self.discard(good, intruder, expect=2)
        self.assertTrue(good.exists())
        self.assertTrue(intruder.exists())
        self.assertEqual(self.batches(), [])


def load_tests(loader, tests, pattern):
    # The inherited cases would otherwise run twice, once per fixture.
    suite = unittest.TestSuite()
    suite.addTests(loader.loadTestsFromTestCase(ScreenRecordCase))
    suite.addTest(
        ScreenRecordFocusedMonitorCase(
            "test_the_focused_output_is_pinned_for_every_segment"
        )
    )
    # Named explicitly, like everything else here: this hook collects nothing by
    # discovery, so a class left out of it is silently never run.
    suite.addTests(loader.loadTestsFromTestCase(DiscardSegmentsGuardCase))
    return suite


if __name__ == "__main__":
    for tool in ("ffmpeg", "ffprobe", "env", "bash"):
        if shutil.which(tool) is None:
            raise SystemExit(f"{tool} is required to run these tests")
    unittest.main(verbosity=2)
