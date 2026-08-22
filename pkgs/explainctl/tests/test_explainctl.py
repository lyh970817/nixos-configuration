from __future__ import annotations

import contextlib
import io
import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from explainctl_lib import core  # noqa: E402
from explainctl_lib import cli  # noqa: E402


OPEN_BLOCK = """\
<!-- explain-question id="q-1111" status="open" -->
> [!QUESTION]
> Where do the cross terms disappear algebraically?
<!-- /explain-question -->
"""

RESOLVED_BLOCK = """\
<!-- explain-question id="q-2222" status="resolved" -->
> [!QUESTION]
> Already answered.
<!-- /explain-question -->
"""


def run_cli(argv):
    stdout = io.StringIO()
    stderr = io.StringIO()
    with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
        code = cli.main(argv)
    try:
        result = json.loads(stdout.getvalue())
    except ValueError:
        raise AssertionError(
            "CLI printed no JSON; exit %r\nstdout: %r\nstderr: %r"
            % (code, stdout.getvalue(), stderr.getvalue())
        ) from None
    return code, result, stderr.getvalue()


class QuestionParsingTest(unittest.TestCase):
    def test_open_and_resolved(self):
        text = "# Doc\n\n" + OPEN_BLOCK + "\nmiddle\n\n" + RESOLVED_BLOCK
        questions = core.parse_questions(text)
        self.assertEqual([q.id for q in questions], ["q-1111", "q-2222"])
        self.assertEqual([q.id for q in core.open_questions(text)], ["q-1111"])

    def test_only_status_open_counts(self):
        for status in ("resolved", "closed", "", "OPEN"):
            block = OPEN_BLOCK.replace('status="open"', f'status="{status}"')
            self.assertEqual(core.open_questions(block), [])

    def test_missing_id_is_ignored(self):
        block = OPEN_BLOCK.replace('id="q-1111" ', "")
        self.assertEqual(core.parse_questions(block), [])

    def test_line_numbers_and_body_text(self):
        text = "line1\nline2\n" + OPEN_BLOCK
        question = core.open_questions(text)[0]
        self.assertEqual(question.line, 3)
        self.assertEqual(
            question.text, "Where do the cross terms disappear algebraically?"
        )

    def test_attribute_order_and_spacing_tolerated(self):
        text = (
            '<!--  explain-question   status="open"  id="q-3333"  -->\n'
            "> [!QUESTION]\n> Why?\n"
            "<!--  /explain-question  -->\n"
        )
        questions = core.open_questions(text)
        self.assertEqual([q.id for q in questions], ["q-3333"])

    def test_unterminated_block_is_ignored(self):
        text = '<!-- explain-question id="q-4444" status="open" -->\n> dangling'
        self.assertEqual(core.parse_questions(text), [])

    def test_tree_scan_skips_hidden_directories(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "explanation.md").write_text(OPEN_BLOCK)
            (root / "children").mkdir()
            (root / "children" / "child.md").write_text(OPEN_BLOCK.replace("1111", "5555"))
            hidden = root / ".staging"
            hidden.mkdir()
            (hidden / "draft.md").write_text(OPEN_BLOCK.replace("1111", "6666"))
            ids = {q.id for q in core.open_questions_in_tree(root)}
            self.assertEqual(ids, {"q-1111", "q-5555"})


class RootResolutionTest(unittest.TestCase):
    def test_resolves_from_nested_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "explanation"
            (root / "children").mkdir(parents=True)
            (root / core.METADATA_NAME).write_text("{}")
            child = root / "children" / "child.md"
            child.write_text("x")
            self.assertEqual(core.resolve_root(child), root)
            self.assertEqual(core.resolve_root(root), root)

    def test_no_metadata_returns_none(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIsNone(core.resolve_root(Path(tmp)))

    def test_root_document_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.assertEqual(
                core.root_document(root, {"root_document": "explanation.md"}),
                (root / "explanation.md").resolve(),
            )
            self.assertEqual(
                core.root_document(root, {}), (root / "explanation.md").resolve()
            )


class SlugTest(unittest.TestCase):
    def test_slugify(self):
        self.assertEqual(
            core.slugify("Why does this estimator remain unbiased?"),
            "why-does-this-estimator-remain-unbiased",
        )
        self.assertEqual(core.slugify("???"), "explanation")

    def test_new_root_unique(self):
        import datetime

        with tempfile.TemporaryDirectory() as tmp:
            store = Path(tmp)
            now = datetime.datetime(2026, 8, 22, 12, 0, 0)
            first = core.new_root(store, "same question", now)
            second = core.new_root(store, "same question", now)
            self.assertNotEqual(first, second)
            self.assertTrue(first.is_dir())
            self.assertTrue(second.is_dir())


class LockTest(unittest.TestCase):
    def test_second_acquire_is_busy_and_reports_owner(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            holder = core.TreeLock(root).acquire("submit", "/some/file.md")
            try:
                with self.assertRaises(core.ExplainBusy) as caught:
                    core.TreeLock(root).acquire("submit")
                self.assertEqual(caught.exception.owner.get("pid"), os.getpid())
                self.assertEqual(caught.exception.owner.get("operation"), "submit")
            finally:
                holder.release()
            # Released: acquirable again, and the file was never deleted.
            core.TreeLock(root).acquire("submit").release()
            self.assertTrue((root / core.LOCK_NAME).exists())

    def test_stale_lock_file_does_not_block(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / core.LOCK_NAME).write_text('{"pid": 999999}')
            lock = core.TreeLock(root).acquire("new")
            lock.release()

    def test_probe_does_not_disturb_diagnostics(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            holder = core.TreeLock(root).acquire("submit", "/a.md")
            try:
                locked, owner = core.TreeLock.probe(root)
                self.assertTrue(locked)
                self.assertEqual(owner.get("submitted"), "/a.md")
            finally:
                holder.release()
            locked, _owner = core.TreeLock.probe(root)
            self.assertFalse(locked)

    def test_lock_file_mode_is_private(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            core.TreeLock(root).acquire("new").release()
            mode = stat.S_IMODE(os.stat(root / core.LOCK_NAME).st_mode)
            self.assertEqual(mode, 0o600)


class SnapshotRestoreTest(unittest.TestCase):
    def _tree(self, tmp):
        root = Path(tmp)
        (root / "explanation.md").write_text("original root\n")
        (root / core.CONTEXT_NAME).write_text("context\n")
        (root / "children").mkdir()
        (root / "children" / "child.md").write_text("original child\n")
        return root

    def test_restore_reverts_edits_and_quarantines_new_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._tree(tmp)
            snapshot = core.snapshot_tree(root)
            (root / "explanation.md").write_text("clobbered\n")
            (root / "children" / "child.md").write_text("also clobbered\n")
            (root / "children" / "rogue.md").write_text("half-written\n")
            outcome = core.restore_snapshot(root, snapshot)
            core.discard_snapshot(snapshot)
            self.assertEqual((root / "explanation.md").read_text(), "original root\n")
            self.assertEqual(
                (root / "children" / "child.md").read_text(), "original child\n"
            )
            self.assertFalse((root / "children" / "rogue.md").exists())
            self.assertEqual(outcome["quarantined"], [str(Path("children/rogue.md"))])
            quarantine = Path(outcome["quarantine_dir"])
            self.assertTrue((quarantine / "children" / "rogue.md").is_file())
            self.assertFalse(snapshot.exists())

    def test_snapshot_is_hidden_from_tree_scans(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._tree(tmp)
            snapshot = core.snapshot_tree(root)
            files = {str(p.relative_to(root)) for p in core.tree_markdown_files(root)}
            self.assertEqual(files, {"explanation.md", str(Path("children/child.md"))})
            core.discard_snapshot(snapshot)

    def test_hash_diff(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._tree(tmp)
            before = core.hash_tree(root)
            (root / "explanation.md").write_text("edited\n")
            (root / "children" / "new.md").write_text("new\n")
            updated, created = core.diff_hashes(before, core.hash_tree(root))
            self.assertEqual(updated, ["explanation.md"])
            self.assertEqual(created, [str(Path("children/new.md"))])


class OriginTest(unittest.TestCase):
    def test_flags_take_precedence(self):
        origin = core.resolve_origin(
            "sid-flag",
            "/tmp",
            "claude-gpt56",
            environ={"CLAUDE_CODE_SESSION_ID": "sid-env"},
        )
        self.assertEqual(origin["session_id"], "sid-flag")
        self.assertEqual(origin["launcher"], "claude-gpt56")
        self.assertIsNone(origin["config_dir"])

    def test_env_fallback_infers_launcher(self):
        origin = core.resolve_origin(
            None,
            None,
            None,
            environ={
                "CLAUDE_CODE_SESSION_ID": "sid-env",
                "CLAUDE_CONFIG_DIR": "/home/user/.config/claude-gpt56",
            },
            process_cwd="/tmp",
        )
        self.assertEqual(origin["session_id"], "sid-env")
        self.assertEqual(origin["launcher"], "claude-gpt56")
        self.assertIsNone(origin["config_dir"])

    def test_unknown_profile_records_config_dir(self):
        origin = core.resolve_origin(
            None,
            None,
            None,
            environ={
                "CLAUDE_CODE_SESSION_ID": "sid-env",
                "CLAUDE_CONFIG_DIR": "/home/user/.config/claude-custom",
            },
            process_cwd="/tmp",
        )
        self.assertIsNone(origin["launcher"])
        self.assertEqual(origin["config_dir"], "/home/user/.config/claude-custom")

    def test_missing_session_is_none(self):
        origin = core.resolve_origin(None, None, None, environ={}, process_cwd="/tmp")
        self.assertIsNone(origin["session_id"])


class TemplateTest(unittest.TestCase):
    def test_render_ignores_latex_braces(self):
        text = "Q: {{question}} and $\\frac{a}{b}$ stays"
        rendered = core.render_template(text, {"question": "why"})
        self.assertEqual(rendered, "Q: why and $\\frac{a}{b}$ stays")

    def test_template_search_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            override = Path(tmp) / "override"
            override.mkdir()
            (override / "bootstrap.md").write_text("OVERRIDE")
            environ = {"EXPLAINCTL_TEMPLATES": str(override)}
            text = core.load_template("bootstrap.md", {"launcher": "claude"}, environ)
            self.assertEqual(text, "OVERRIDE")
            with self.assertRaises(FileNotFoundError):
                core.load_template(
                    "missing.md", {"launcher": "claude"}, {"XDG_CONFIG_HOME": tmp}
                )


class ClaudeOutputTest(unittest.TestCase):
    def test_whole_stdout_json(self):
        data = cli.parse_claude_output('{"session_id": "abc", "result": "ok"}')
        self.assertEqual(data["session_id"], "abc")

    def test_last_json_line_fallback(self):
        stdout = 'warning: something\n{"session_id": "abc"}\n'
        self.assertEqual(cli.parse_claude_output(stdout)["session_id"], "abc")

    def test_garbage_raises(self):
        with self.assertRaises(cli.CommandError):
            cli.parse_claude_output("not json at all")


class CliBusyTest(unittest.TestCase):
    def test_submit_on_locked_tree_exits_75(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            core.write_metadata(
                root,
                {
                    "version": 1,
                    "status": "ready",
                    "coordinator_session_id": "coord",
                    "root_document": "explanation.md",
                    "origin": {"launcher": "claude", "cwd": tmp, "config_dir": None},
                },
            )
            document = root / "explanation.md"
            document.write_text(OPEN_BLOCK)
            holder = core.TreeLock(root).acquire("submit", str(document))
            try:
                code, result, _err = run_cli(["submit", str(document)])
            finally:
                holder.release()
            self.assertEqual(code, core.EX_BUSY)
            self.assertEqual(result["status"], "busy")
            self.assertEqual(result["active_pid"], os.getpid())
            self.assertEqual(result["submitted"], str(document))
            # The user's question block survives the busy response.
            self.assertIn("q-1111", document.read_text())

    def test_submit_without_open_questions_makes_no_model_call(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            core.write_metadata(
                root,
                {
                    "version": 1,
                    "status": "ready",
                    "coordinator_session_id": "coord",
                    "root_document": "explanation.md",
                    "origin": {"launcher": "claude", "cwd": tmp, "config_dir": None},
                },
            )
            document = root / "explanation.md"
            document.write_text(RESOLVED_BLOCK)
            code, result, _err = run_cli(["submit", str(document)])
            self.assertEqual(code, 0)
            self.assertEqual(result["status"], "no_questions")

    def test_submit_outside_tree_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            document = Path(tmp) / "stray.md"
            document.write_text("x")
            code, result, _err = run_cli(["submit", str(document)])
            self.assertEqual(code, 1)
            self.assertEqual(result["status"], "failed")


class CliNewTest(unittest.TestCase):
    """End-to-end `new --no-open` against a stub claude binary."""

    def _fake_claude(self, tmp, body):
        # The shebang names the running interpreter directly: /usr/bin/env
        # does not exist inside the Nix build sandbox, and a failed shebang
        # exec is indistinguishable from a missing launcher.
        fake = Path(tmp) / "fake-claude"
        fake.write_text("#!%s\n" % sys.executable + body)
        fake.chmod(0o755)
        return fake

    def test_new_creates_ready_tree(self):
        with tempfile.TemporaryDirectory() as tmp:
            templates = Path(tmp) / "templates"
            templates.mkdir()
            (templates / "bootstrap.md").write_text(
                "Question: {{question}}\nWrite {{root_document}}\n"
            )
            fake = self._fake_claude(
                tmp,
                """
import json, os, sys
argv = sys.argv[1:]
prompt = argv[argv.index("-p") + 1]
root = argv[argv.index("--add-dir") + 1]
staging = os.path.join(root, ".staging")
with open(os.path.join(staging, "explanation.md"), "w") as fh:
    fh.write("# Explanation\\n\\nBody derived from: " + prompt[:40] + "\\n")
with open(os.path.join(staging, ".context.md"), "w") as fh:
    fh.write("context notes\\n")
assert "--fork-session" in argv
assert "--resume" in argv
print(json.dumps({"session_id": "fork-123", "result": "done"}))
""",
            )
            environ = {
                "XDG_DATA_HOME": str(Path(tmp) / "data"),
                "EXPLAINCTL_TEMPLATES": str(templates),
                "EXPLAINCTL_CLAUDE_BIN": str(fake),
            }
            old = {key: os.environ.get(key) for key in environ}
            os.environ.update(environ)
            try:
                code, result, _err = run_cli(
                    [
                        "new",
                        "--question",
                        "Why is the estimator unbiased?",
                        "--session-id",
                        "origin-999",
                        "--cwd",
                        tmp,
                        "--launcher",
                        "claude",
                        "--no-open",
                    ]
                )
            finally:
                for key, value in old.items():
                    if value is None:
                        os.environ.pop(key, None)
                    else:
                        os.environ[key] = value
            self.assertEqual(code, 0, msg=f"result={result!r} stderr={_err!r}")
            self.assertEqual(result["status"], "created")
            self.assertEqual(result["session_id"], "fork-123")
            self.assertEqual(result["origin_session_id"], "origin-999")
            self.assertFalse(result["opened"])
            root = Path(result["root"])
            self.assertEqual(result["focus"], str(root / "explanation.md"))
            self.assertTrue((root / "explanation.md").is_file())
            self.assertTrue((root / ".context.md").is_file())
            self.assertFalse((root / ".staging").exists())
            metadata = core.read_metadata(root)
            self.assertEqual(metadata["status"], "ready")
            self.assertEqual(metadata["coordinator_session_id"], "fork-123")
            self.assertEqual(metadata["root_document"], "explanation.md")
            self.assertEqual(metadata["origin"]["launcher"], "claude")
            # No secrets anywhere in the metadata.
            self.assertNotIn("token", json.dumps(metadata).lower())
            locked, _ = core.TreeLock.probe(root)
            self.assertFalse(locked)

    def test_new_failure_marks_failed_and_keeps_staging(self):
        with tempfile.TemporaryDirectory() as tmp:
            templates = Path(tmp) / "templates"
            templates.mkdir()
            (templates / "bootstrap.md").write_text("prompt")
            fake = self._fake_claude(tmp, "import sys\nsys.exit(3)\n")
            environ = {
                "XDG_DATA_HOME": str(Path(tmp) / "data"),
                "EXPLAINCTL_TEMPLATES": str(templates),
                "EXPLAINCTL_CLAUDE_BIN": str(fake),
            }
            old = {key: os.environ.get(key) for key in environ}
            os.environ.update(environ)
            try:
                code, result, _err = run_cli(
                    [
                        "new",
                        "--question",
                        "q",
                        "--session-id",
                        "origin-999",
                        "--cwd",
                        tmp,
                        "--launcher",
                        "claude",
                        "--no-open",
                    ]
                )
            finally:
                for key, value in old.items():
                    if value is None:
                        os.environ.pop(key, None)
                    else:
                        os.environ[key] = value
            self.assertEqual(code, 1)
            self.assertEqual(result["status"], "failed")
            root = Path(result["root"])
            metadata = core.read_metadata(root)
            self.assertEqual(metadata["status"], "failed")
            locked, _ = core.TreeLock.probe(root)
            self.assertFalse(locked)

    def test_new_without_session_fails_clearly(self):
        old = os.environ.pop("CLAUDE_CODE_SESSION_ID", None)
        try:
            code, result, _err = run_cli(["new", "--question", "q", "--no-open"])
        finally:
            if old is not None:
                os.environ["CLAUDE_CODE_SESSION_ID"] = old
        self.assertEqual(code, 1)
        self.assertEqual(result["status"], "failed")
        self.assertIn("session", result["message"])


if __name__ == "__main__":
    unittest.main()
