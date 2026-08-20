#!/usr/bin/env python3

import asyncio
import base64
import importlib.util
import json
import pathlib
import sys
import types
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "qwen-asr-shim.py"

# The production service gets these modules from qwenAsrShimPython. These
# focused unit tests exercise protocol-independent helpers and do not need the
# native/runtime dependencies themselves.
sys.modules.setdefault("numpy", types.SimpleNamespace())
class _FakeConnectionClosed(Exception):
    pass


sys.modules.setdefault(
    "websockets",
    types.SimpleNamespace(
        exceptions=types.SimpleNamespace(ConnectionClosed=_FakeConnectionClosed),
    ),
)
spec = importlib.util.spec_from_file_location("qwen_asr_shim", SCRIPT)
shim = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shim)


def append_event(pcm, event_id=None):
    event = {
        "type": "input_audio_buffer.append",
        "audio": base64.b64encode(pcm).decode("ascii"),
    }
    if event_id:
        event["event_id"] = event_id
    return event


def decoded_bytes(event):
    return base64.b64decode(event["audio"])


class SegmentedAudioBufferTests(unittest.TestCase):
    def test_short_audio_gets_one_final_commit(self):
        buffer = shim._SegmentedAudioBuffer(max_bytes=8)

        events = buffer.push(append_event(b"\x01\x00" * 3))
        events += buffer.finish({"type": "input_audio_buffer.commit"})

        self.assertEqual([kind for _, kind in events], [None, "final"])
        self.assertEqual(decoded_bytes(events[0][0]), b"\x01\x00" * 3)
        self.assertEqual(buffer.commits, 1)
        self.assertEqual(buffer.automatic_commits, 0)

    def test_large_append_is_split_and_every_full_segment_is_committed(self):
        buffer = shim._SegmentedAudioBuffer(max_bytes=8)

        events = buffer.push(append_event(bytes(range(20)), event_id="client-1"))
        events += buffer.finish({"type": "input_audio_buffer.commit"})

        self.assertEqual(
            [kind for _, kind in events],
            [None, "automatic", None, "automatic", None, "final"],
        )
        appends = [event for event, kind in events if kind is None]
        self.assertEqual([len(decoded_bytes(event)) for event in appends], [8, 8, 4])
        self.assertEqual(b"".join(decoded_bytes(event) for event in appends), bytes(range(20)))
        self.assertTrue(all("event_id" not in event for event in appends))
        self.assertEqual(buffer.commits, 3)
        self.assertEqual(buffer.automatic_commits, 2)

    def test_exact_boundary_does_not_emit_an_empty_final_commit(self):
        buffer = shim._SegmentedAudioBuffer(max_bytes=8)

        events = buffer.push(append_event(b"\x01\x00" * 4))
        final = buffer.finish({"type": "input_audio_buffer.commit"})

        self.assertEqual([kind for _, kind in events], [None, "automatic"])
        self.assertEqual(final, [])
        self.assertEqual(buffer.commits, 1)

    def test_empty_buffer_does_not_commit(self):
        buffer = shim._SegmentedAudioBuffer(max_bytes=8)

        self.assertEqual(
            buffer.finish({"type": "input_audio_buffer.commit"}),
            [],
        )
        self.assertEqual(buffer.commits, 0)

    def test_malformed_audio_is_still_committed_for_provider_validation(self):
        buffer = shim._SegmentedAudioBuffer(max_bytes=8)
        malformed = {
            "type": "input_audio_buffer.append",
            "audio": "not valid base64",
        }

        events = buffer.push(malformed)
        events += buffer.finish({"type": "input_audio_buffer.commit"})

        self.assertEqual(events, [(malformed, None), (
            {"type": "input_audio_buffer.commit"}, "final"
        )])

    def test_clear_discards_partial_segment_and_counters(self):
        buffer = shim._SegmentedAudioBuffer(max_bytes=8)
        buffer.push(append_event(b"\x01\x00" * 3))

        buffer.clear()

        self.assertEqual(buffer.buffered_bytes, 0)
        self.assertEqual(buffer.total_bytes, 0)
        self.assertEqual(buffer.commits, 0)


class RawTranscriptAccumulatorTests(unittest.TestCase):
    def test_combines_committed_items_in_completion_order(self):
        raw = shim._RawTranscriptAccumulator()

        raw.add_completed({"item_id": "one", "transcript": "first part"})
        raw.add_completed({"item_id": "two", "text": "second part"})

        self.assertEqual(raw.text, "first part second part")
        self.assertEqual(raw.completed_items, 2)

    def test_uses_commit_order_when_completions_arrive_out_of_order(self):
        raw = shim._RawTranscriptAccumulator()
        raw.record_committed("one")
        raw.record_committed("two")

        raw.add_completed({"item_id": "two", "transcript": "second part"})
        raw.add_completed({"item_id": "one", "transcript": "first part"})

        self.assertEqual(raw.text, "first part second part")

    def test_item_update_does_not_duplicate_transcript(self):
        raw = shim._RawTranscriptAccumulator()
        raw.add_completed({"item_id": "one", "transcript": "partial"})
        raw.add_completed({"item_id": "one", "transcript": "complete"})

        self.assertEqual(raw.text, "complete")

    def test_clear_removes_every_segment(self):
        raw = shim._RawTranscriptAccumulator()
        raw.add_completed({"item_id": "one", "transcript": "first"})
        raw.add_completed({"transcript": "unkeyed"})

        raw.clear()

        self.assertEqual(raw.text, "")
        self.assertEqual(raw.completed_items, 0)


class _FakeUpstream:
    def __init__(
        self,
        response_text="complete cleaned transcript covering all three linked segments",
        raw_on_commit=3,
        delay_first_item_events=False,
        item_prefix="",
    ):
        self.received = []
        self.events = asyncio.Queue()
        self.commit_count = 0
        self.response_text = response_text
        self.raw_on_commit = raw_on_commit
        self.delay_first_item_events = delay_first_item_events
        self.item_prefix = item_prefix
        self.closed = False

    async def send(self, raw):
        event = json.loads(raw)
        self.received.append(event)
        if event["type"] == "input_audio_buffer.commit":
            self.commit_count += 1
            item_id = f"{self.item_prefix}audio-{self.commit_count}"
            await self.events.put(json.dumps({
                "type": "input_audio_buffer.committed",
                "item_id": item_id,
            }))
            if not (self.delay_first_item_events and self.commit_count == 1):
                await self.events.put(json.dumps({
                    "type": "conversation.item.created",
                    "item": {"id": item_id},
                }))
            if self.commit_count == self.raw_on_commit:
                # This matches the observed Audio3 multi-commit behavior: one
                # raw completion associated with only the final audio item.
                await self.events.put(json.dumps({
                    "type": "conversation.item.input_audio_transcription.completed",
                    "item_id": item_id,
                    "transcript": "last segment",
                }))
        elif event["type"] == "response.create":
            await self.events.put(json.dumps({
                "type": "response.text.done",
                "text": self.response_text,
            }))
            await self.events.put(json.dumps({
                "type": "response.done",
                "response": {"status": "completed"},
            }))

    def __aiter__(self):
        return self

    async def __anext__(self):
        event = await self.events.get()
        if event is None:
            raise StopAsyncIteration
        return event

    async def close(self):
        self.closed = True
        if self.delay_first_item_events and self.commit_count:
            # Events already in flight from the canceled old session can be
            # delivered while that connection is closing.
            await self.events.put(json.dumps({
                "type": "conversation.item.created",
                "item": {"id": f"{self.item_prefix}audio-1"},
            }))
            await self.events.put(json.dumps({
                "type": "conversation.item.input_audio_transcription.completed",
                "item_id": f"{self.item_prefix}audio-1",
                "transcript": "stale cancelled transcript",
            }))
        await self.events.put(None)


class _DisconnectOnAppendUpstream(_FakeUpstream):
    async def send(self, raw):
        event = json.loads(raw)
        if event["type"] == "input_audio_buffer.append":
            self.received.append(event)
            await self.events.put(_FakeConnectionClosed("simulated disconnect"))
            return
        await super().send(raw)

    async def __anext__(self):
        event = await self.events.get()
        if isinstance(event, _FakeConnectionClosed):
            raise event
        if event is None:
            raise StopAsyncIteration
        return event


class _FakeClient:
    def __init__(self, events, response_on_commit=None):
        self.incoming = asyncio.Queue()
        for event in events:
            self.incoming.put_nowait(json.dumps(event))
        self.sent = []
        self.closed = False
        self.response_on_commit = response_on_commit

    def __aiter__(self):
        return self

    async def __anext__(self):
        event = await self.incoming.get()
        if event is None:
            raise StopAsyncIteration
        return event

    async def send(self, raw):
        event = json.loads(raw)
        self.sent.append(event)
        if (
            event["type"] == "input_audio_buffer.committed"
            and self.response_on_commit is not None
        ):
            await self.incoming.put(json.dumps(self.response_on_commit))
            self.response_on_commit = None
        if event["type"] == "response.done":
            await self.incoming.put(None)

    async def close(self, code=None):
        self.closed = True
        while not self.incoming.empty():
            self.incoming.get_nowait()
        await self.incoming.put(None)


class RealtimeTranslatorTests(unittest.IsolatedAsyncioTestCase):
    async def test_in_flight_disconnect_fails_instead_of_returning_a_suffix(self):
        upstream = _DisconnectOnAppendUpstream()
        client = _FakeClient([
            {"type": "input_audio_buffer.clear"},
            append_event(bytes(range(8))),
            {"type": "input_audio_buffer.commit"},
            {"type": "response.create", "response": {}},
        ])
        translator = shim.RealtimeTranslator(
            "test", "wss://invalid.example", 0, max_segment_bytes=8
        )

        async def open_upstream():
            return upstream

        translator.open_upstream = open_upstream
        with mock.patch.object(
            shim._RealtimeSilenceGate,
            "_rms",
            staticmethod(lambda _msg: 1000.0),
        ):
            await asyncio.wait_for(translator.handle_client(client), timeout=1)

        self.assertTrue(client.closed)
        self.assertNotIn(
            "response.create",
            [event["type"] for event in upstream.received],
        )
        self.assertFalse(any(
            event["type"] == "response.output_text.done"
            for event in client.sent
        ))

    async def test_clear_replaces_session_after_committed_cancelled_utterance(self):
        old_upstream = _FakeUpstream(
            delay_first_item_events=True,
            item_prefix="old-",
        )
        new_upstream = _FakeUpstream(
            response_text="Sure, here is an answer.",
            raw_on_commit=1,
            item_prefix="new-",
        )
        client = _FakeClient([
            {"type": "input_audio_buffer.clear"},
            append_event(bytes(range(8))),
            # Cancel/reset after the automatic boundary commit, without a
            # response for the first utterance.
            {"type": "input_audio_buffer.clear"},
            append_event(bytes(range(4))),
            {"type": "input_audio_buffer.commit"},
            {"type": "response.create", "response": {}},
        ])
        translator = shim.RealtimeTranslator(
            "test", "wss://invalid.example", 0, max_segment_bytes=8
        )

        upstreams = iter([old_upstream, new_upstream])
        open_count = 0

        async def open_upstream():
            nonlocal open_count
            open_count += 1
            if open_count == 2:
                # Let the reader observe conn["ws"] == None and enter its
                # readiness wait before publishing the replacement.
                await asyncio.sleep(0)
                await asyncio.sleep(0)
            return next(upstreams)

        translator.open_upstream = open_upstream
        with mock.patch.object(
            shim._RealtimeSilenceGate,
            "_rms",
            staticmethod(lambda _msg: 1000.0),
        ):
            await asyncio.wait_for(translator.handle_client(client), timeout=1)

        self.assertTrue(old_upstream.closed)
        self.assertEqual(
            [event["type"] for event in old_upstream.received],
            [
                "input_audio_buffer.clear",
                "input_audio_buffer.append",
                "input_audio_buffer.commit",
            ],
        )
        self.assertEqual(
            [
                event["type"] for event in new_upstream.received
                if event["type"] != "conversation.item.delete"
            ],
            [
                "input_audio_buffer.clear",
                "input_audio_buffer.append",
                "input_audio_buffer.commit",
                "response.create",
            ],
        )
        cleaned = next(
            event["text"] for event in client.sent
            if event["type"] == "response.output_text.done"
        )
        self.assertEqual(cleaned, "last segment")
        forwarded_ids = [
            (event.get("item") or {}).get("id")
            for event in client.sent
            if event["type"] == "conversation.item.created"
        ]
        self.assertNotIn("old-audio-1", forwarded_ids)

    async def test_multiple_commits_wait_then_one_response_and_keep_full_cleaned_text(self):
        upstream = _FakeUpstream()
        client = _FakeClient([
            {"type": "input_audio_buffer.clear"},
            append_event(bytes(range(20))),
            {"type": "input_audio_buffer.commit"},
            {
                "type": "response.create",
                "response": {
                    "metadata": {"hyprwhspr_request_id": "request-1"},
                },
            },
        ])
        translator = shim.RealtimeTranslator(
            "test", "wss://invalid.example", 0, max_segment_bytes=8
        )

        async def open_upstream():
            return upstream

        translator.open_upstream = open_upstream
        with mock.patch.object(
            shim._RealtimeSilenceGate,
            "_rms",
            staticmethod(lambda _msg: 1000.0),
        ):
            await asyncio.wait_for(translator.handle_client(client), timeout=1)

        upstream_types = [event["type"] for event in upstream.received]
        protocol_types = [
            event_type
            for event_type in upstream_types
            if event_type != "conversation.item.delete"
        ]
        self.assertEqual(
            protocol_types,
            [
                "input_audio_buffer.clear",
                "input_audio_buffer.append",
                "input_audio_buffer.commit",
                "input_audio_buffer.append",
                "input_audio_buffer.commit",
                "input_audio_buffer.append",
                "input_audio_buffer.commit",
                "response.create",
            ],
        )
        self.assertEqual(protocol_types.count("response.create"), 1)
        client_commits = [
            event for event in client.sent
            if event["type"] == "input_audio_buffer.committed"
        ]
        self.assertEqual(len(client_commits), 1)
        cleaned = next(
            event["text"] for event in client.sent
            if event["type"] == "response.output_text.done"
        )
        self.assertEqual(
            cleaned,
            "complete cleaned transcript covering all three linked segments",
        )
        self.assertFalse(client.closed)

    async def test_partial_raw_still_protects_against_boilerplate_reply(self):
        upstream = _FakeUpstream(response_text="Sure, here is an answer to your question.")
        client = _FakeClient([
            {"type": "input_audio_buffer.clear"},
            append_event(bytes(range(20))),
            {"type": "input_audio_buffer.commit"},
            {"type": "response.create", "response": {}},
        ])
        translator = shim.RealtimeTranslator(
            "test", "wss://invalid.example", 0, max_segment_bytes=8
        )

        async def open_upstream():
            return upstream

        translator.open_upstream = open_upstream
        with mock.patch.object(
            shim._RealtimeSilenceGate,
            "_rms",
            staticmethod(lambda _msg: 1000.0),
        ):
            await asyncio.wait_for(translator.handle_client(client), timeout=1)

        cleaned = next(
            event["text"] for event in client.sent
            if event["type"] == "response.output_text.done"
        )
        self.assertEqual(cleaned, "last segment")

    async def test_empty_audio_is_acknowledged_and_completed_locally(self):
        upstream = _FakeUpstream()
        client = _FakeClient(
            [
                {"type": "input_audio_buffer.clear"},
                {"type": "input_audio_buffer.commit"},
            ],
            response_on_commit={
                "type": "response.create",
                "response": {
                    "metadata": {"hyprwhspr_request_id": "empty-request"},
                },
            },
        )
        translator = shim.RealtimeTranslator(
            "test", "wss://invalid.example", 0, max_segment_bytes=8
        )

        async def open_upstream():
            return upstream

        translator.open_upstream = open_upstream
        await asyncio.wait_for(translator.handle_client(client), timeout=1)

        self.assertEqual(
            [event["type"] for event in upstream.received],
            ["input_audio_buffer.clear"],
        )
        self.assertEqual(
            [event["type"] for event in client.sent],
            [
                "input_audio_buffer.committed",
                "response.output_text.done",
                "response.done",
            ],
        )
        for event in client.sent[1:]:
            self.assertEqual(
                event["metadata"],
                {"hyprwhspr_request_id": "empty-request"},
            )


if __name__ == "__main__":
    unittest.main()
