"""Recording status as one desktop notification, replacing the overlay.

Installed by pkgs/doubao-say.nix as doubao_input.ui.notification_overlay. It
mirrors hyprwhspr's notification presenter so both dictation engines look the
same in mako: one transient bubble replaced in place -- "● Recording…", then
"Transcribing…", then "✓ Inserted" for two seconds -- and closed on cancel.
The overlay's live text, waveform and update dot are dropped. A failed paste
just closes the bubble: the app already posts its own recovery notification.
"""
from __future__ import annotations

import logging
import queue
import threading

from gi.repository import Gio, GLib  # type: ignore

logger = logging.getLogger(__name__)

APP_NAME = "doubao-say"
RECORDING = "● Recording…"
TRANSCRIBING = "Transcribing…"
POLISHING = "Polishing…"
INSERTED = "✓ Inserted"
# Active states stay until replaced, as with hyprwhspr's
# notification_timeout_ms = 0; the finished state expires on its own.
ACTIVE_TIMEOUT_MS = 0
DONE_TIMEOUT_MS = 2000


class NotificationOverlay:
    """The subset of Overlay the app drives, backed by one notification."""

    def __init__(self, app_state=None) -> None:
        # Set by the app from its appearance settings; nothing to draw.
        self.reduced_motion = False
        self.waveform_style = "bars"
        self._nid = 0
        self._summary = None
        # D-Bus calls run in order on one worker so callers on the GTK and
        # audio threads never block on the notification server.
        self._queue = queue.SimpleQueue()
        threading.Thread(target=self._run, name="doubao-notify", daemon=True).start()
        if app_state is not None:
            app_state.connect("recording-state-changed", self._on_recording_state_changed)

    def show(self, status: str | None = None) -> None:
        self._queue.put((RECORDING, ACTIVE_TIMEOUT_MS))

    def show_polishing(self, text: str) -> None:
        self._queue.put((POLISHING, ACTIVE_TIMEOUT_MS))

    def finish(self, status: str) -> None:
        if status == "attempted":
            self._queue.put((INSERTED, DONE_TIMEOUT_MS))
        else:
            self._queue.put(None)

    def hide(self) -> None:
        self._queue.put(None)

    def set_text(self, text: str) -> None:
        pass

    def set_status(self, status: str) -> None:
        pass

    def set_update(self, info) -> None:
        pass

    def push_rms(self, rms: float) -> None:
        pass

    def on_keystroke(self) -> None:
        pass

    def _on_recording_state_changed(self, _state, value: str) -> None:
        if value in ("starting", "recording"):
            self._queue.put((RECORDING, ACTIVE_TIMEOUT_MS))
        elif value == "stopping":
            self._queue.put((TRANSCRIBING, ACTIVE_TIMEOUT_MS))

    def _run(self) -> None:
        bus = None
        while True:
            item = self._queue.get()
            try:
                bus = bus or Gio.bus_get_sync(Gio.BusType.SESSION, None)
                if item is None:
                    self._close(bus)
                else:
                    self._notify(bus, *item)
            except GLib.Error as error:
                logger.warning("Status notification failed: %s", error.message)

    def _notify(self, bus, summary: str, timeout_ms: int) -> None:
        if self._nid and summary == self._summary:
            return
        hints = {
            "transient": GLib.Variant("b", True),
            "urgency": GLib.Variant("y", 1),
        }
        reply = bus.call_sync(
            "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
            "org.freedesktop.Notifications", "Notify",
            GLib.Variant("(susssasa{sv}i)",
                         (APP_NAME, self._nid, "", summary, "", [], hints, timeout_ms)),
            GLib.VariantType.new("(u)"), Gio.DBusCallFlags.NONE, 2000, None)
        if timeout_ms == ACTIVE_TIMEOUT_MS:
            self._nid, self._summary = reply.unpack()[0], summary
        else:
            # Let the finished bubble expire; the next recording starts fresh.
            self._nid, self._summary = 0, None

    def _close(self, bus) -> None:
        if not self._nid:
            return
        nid, self._nid, self._summary = self._nid, 0, None
        bus.call_sync(
            "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
            "org.freedesktop.Notifications", "CloseNotification",
            GLib.Variant("(u)", (nid,)), None, Gio.DBusCallFlags.NONE, 2000, None)
