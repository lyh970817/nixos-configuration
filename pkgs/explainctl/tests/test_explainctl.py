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


# A t2l-shaped stub binary: LATEX -> TYPST inside the delimiters, display
# emitted as Typst's padded `$ ... $`, matching the real CLI's output shape.
FAKE_T2L_BODY = """
import sys
src = sys.stdin.read().strip()
def conv(s):
    return s.replace("LATEX", "TYPST")
if src.startswith("$$") and src.endswith("$$"):
    print("$ " + conv(src[2:-2]) + " $")
else:
    print("$" + conv(src[1:-1]) + "$")
"""


def make_fake_bin(tmp, name, body):
    # The shebang names the running interpreter directly: /usr/bin/env does
    # not exist inside the Nix build sandbox.
    fake = Path(tmp) / name
    fake.write_text("#!%s\n" % sys.executable + body)
    fake.chmod(0o755)
    return fake


@contextlib.contextmanager
def patched_env(**environ):
    old = {key: os.environ.get(key) for key in environ}
    os.environ.update(environ)
    try:
        yield
    finally:
        for key, value in old.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


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


class StagingTest(unittest.TestCase):
    def _tree(self, tmp):
        root = Path(tmp)
        (root / "explanation.md").write_text("original root\n")
        (root / core.CONTEXT_NAME).write_text("context\n")
        (root / "children").mkdir()
        (root / "children" / "child.md").write_text("original child\n")
        return root

    def test_stage_copies_markdown_and_context(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._tree(tmp)
            staging = core.stage_tree(root)
            staged = {
                str(p.relative_to(staging)) for p in core.staged_targets(staging)
            }
            self.assertEqual(
                staged,
                {"explanation.md", str(Path("children/child.md")), core.CONTEXT_NAME},
            )
            # Editing the staging copy leaves the live tree alone.
            (staging / "explanation.md").write_text("edited in staging\n")
            self.assertEqual((root / "explanation.md").read_text(), "original root\n")
            core.discard_staging(staging)
            self.assertFalse(staging.exists())

    def test_staging_is_hidden_from_tree_scans(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._tree(tmp)
            staging = core.stage_tree(root)
            files = {str(p.relative_to(root)) for p in core.tree_markdown_files(root)}
            self.assertEqual(files, {"explanation.md", str(Path("children/child.md"))})
            self.assertEqual(core.hash_tree(root), core.hash_tree(root))
            core.discard_staging(staging)

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


class JsonCompatFlagTest(unittest.TestCase):
    """`--json` is a no-op accepted anywhere: JSON is always printed. The F7
    regression was argparse exiting 2 on `submit --json f` because a
    parent-parser optional is never matched after subcommand dispatch."""

    def test_json_flag_accepted_in_both_positions(self):
        parser = cli.build_parser()
        for argv in (
            ["submit", "--json", "some.md"],
            ["--json", "submit", "some.md"],
            ["new", "--question", "q", "--json", "--no-open"],
            ["new", "--pending", "--json", "--no-open"],
            ["status", "--json"],
            ["list", "--json"],
            ["sync", "target", "--json"],
            ["open", "target", "--json"],
            ["migrate-typst", "--all", "--json"],
            ["migrate-typst", "target", "--json"],
            ["doctor", "--json"],
        ):
            try:
                parser.parse_args(argv)  # exits 2 on unrecognized arguments
            except SystemExit as error:
                self.fail(f"parser rejected {argv}: exit {error.code}")


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


class CliSubmitProtocolTest(unittest.TestCase):
    """End-to-end submit against stub claude/t2l binaries: the agent edits a
    staging copy, the result is converted to Typst and committed only if the
    live tree is unchanged."""

    # Edits the staging directory received via --add-dir: resolves the open
    # question, appends an answer carrying LaTeX math, creates a child.
    AGENT_BODY = """
import json, os, sys
argv = sys.argv[1:]
staging = argv[argv.index("--add-dir") + 1]
doc = os.path.join(staging, "explanation.md")
with open(doc) as fh:
    text = fh.read()
text = text.replace('status="open"', 'status="resolved"')
text += "\\nAnswer: the rate is $LATEX$ exactly.\\n"
with open(doc, "w") as fh:
    fh.write(text)
os.makedirs(os.path.join(staging, "children"), exist_ok=True)
with open(os.path.join(staging, "children", "detour.md"), "w") as fh:
    fh.write("# Detour\\n\\n$$LATEX$$\\n")
print(json.dumps({"result": "done"}))
"""

    # Same, but also clobbers the LIVE tree (staging's parent) mid-run, the
    # way a laptop rsync push would.
    CONFLICT_BODY = AGENT_BODY.replace(
        'print(json.dumps({"result": "done"}))',
        """
root = os.path.dirname(staging)
with open(os.path.join(root, "explanation.md"), "a") as fh:
    fh.write("\\nconcurrent user edit\\n")
print(json.dumps({"result": "done"}))
""",
    )

    def _tree(self, tmp, math_syntax="typst"):
        root = Path(tmp) / "tree"
        root.mkdir()
        metadata = {
            "version": 1,
            "status": "ready",
            "coordinator_session_id": "coord",
            "root_document": "explanation.md",
            "origin": {"launcher": "claude", "cwd": tmp, "config_dir": None},
            "math_syntax": math_syntax,
        }
        core.write_metadata(root, metadata)
        (root / "explanation.md").write_text(
            "# Doc\n\nOld math $LATEX$ must stay LaTeX-shaped.\n\n" + OPEN_BLOCK
        )
        (root / core.CONTEXT_NAME).write_text("notes\n")
        return root

    def _env(self, tmp, agent_body):
        templates = Path(tmp) / "templates"
        templates.mkdir()
        (templates / "update.md").write_text(
            "Root {{explanation_root}}; submitted {{submitted}};\n{{questions}}\n"
        )
        return {
            "EXPLAINCTL_TEMPLATES": str(templates),
            "EXPLAINCTL_CLAUDE_BIN": str(make_fake_bin(tmp, "fake-claude", agent_body)),
            "EXPLAINCTL_T2L": str(make_fake_bin(tmp, "fake-t2l", FAKE_T2L_BODY)),
        }

    def test_submit_converts_new_math_and_commits(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._tree(tmp)
            document = root / "explanation.md"
            with patched_env(**self._env(tmp, self.AGENT_BODY)):
                code, result, _err = run_cli(["submit", str(document)])
            self.assertEqual(code, 0, msg=repr(result))
            self.assertEqual(result["status"], "updated")
            text = document.read_text()
            # The agent's new math was converted, pre-existing content was
            # not re-run through the converter.
            self.assertIn("the rate is $TYPST$ exactly.", text)
            self.assertIn("Old math $LATEX$ must stay", text)
            self.assertIn('status="resolved"', text)
            child = root / "children" / "detour.md"
            self.assertEqual(child.read_text(), "# Detour\n\n$$TYPST$$\n")
            self.assertEqual(result["resolved_question_ids"], ["q-1111"])
            self.assertEqual(result["created"], [str(child)])
            self.assertEqual(result["focus"], str(child))
            # Staging is gone and the lock is free.
            self.assertEqual(list(root.glob(".submit-*")), [])
            locked, _ = core.TreeLock.probe(root)
            self.assertFalse(locked)

    def test_submit_without_typst_marker_skips_conversion(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._tree(tmp, math_syntax="latex")
            document = root / "explanation.md"
            with patched_env(**self._env(tmp, self.AGENT_BODY)):
                code, result, _err = run_cli(["submit", str(document)])
            self.assertEqual(code, 0)
            self.assertEqual(result["status"], "updated")
            self.assertIn("the rate is $LATEX$ exactly.", document.read_text())

    def test_concurrent_live_edit_aborts_with_conflict(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._tree(tmp)
            document = root / "explanation.md"
            with patched_env(**self._env(tmp, self.CONFLICT_BODY)):
                code, result, _err = run_cli(["submit", str(document)])
            self.assertEqual(code, 1)
            self.assertEqual(result["status"], "conflict")
            self.assertEqual(result["conflicting_files"], ["explanation.md"])
            # Live tree keeps the concurrent edit, never the agent's answer.
            text = document.read_text()
            self.assertIn("concurrent user edit", text)
            self.assertNotIn("the rate is", text)
            self.assertIn('status="open"', text)
            self.assertFalse((root / "children" / "detour.md").exists())
            # The staged result is preserved for inspection.
            staged = Path(result["staged"])
            self.assertTrue(staged.is_dir())
            self.assertIn(
                "the rate is $LATEX$", (staged / "explanation.md").read_text()
            )
            locked, _ = core.TreeLock.probe(root)
            self.assertFalse(locked)


class CliMigrateTypstTest(unittest.TestCase):
    def _store_tree(self, store, name, text="Math $LATEX$ here.\n"):
        root = store / name
        root.mkdir(parents=True)
        core.write_metadata(
            root,
            {
                "version": 1,
                "status": "ready",
                "slug": name,
                "root_document": "explanation.md",
            },
        )
        (root / "explanation.md").write_text(text)
        return root

    def test_migrate_converts_marks_and_skips_on_rerun(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = Path(tmp) / "data" / "explanations"
            root = self._store_tree(
                store,
                "20260101-000000-demo",
                "Inline $LATEX$ and\n\n```\ncode $LATEX$\n```\n\n$$LATEX$$\n",
            )
            env = {
                "XDG_DATA_HOME": str(Path(tmp) / "data"),
                "EXPLAINCTL_T2L": str(
                    make_fake_bin(tmp, "fake-t2l", FAKE_T2L_BODY)
                ),
            }
            with patched_env(**env):
                code, result, _err = run_cli(["migrate-typst", str(root)])
                self.assertEqual(code, 0, msg=repr(result))
                self.assertEqual(result["trees"][0]["status"], "migrated")
                text = (root / "explanation.md").read_text()
                self.assertEqual(
                    text, "Inline $TYPST$ and\n\n```\ncode $LATEX$\n```\n\n$$TYPST$$\n"
                )
                self.assertTrue(core.tree_is_typst(core.read_metadata(root)))
                # Idempotence: a second run must not touch the files again.
                code, result, _err = run_cli(["migrate-typst", str(root)])
                self.assertEqual(code, 0)
                self.assertEqual(result["trees"][0]["status"], "skipped")
                self.assertEqual((root / "explanation.md").read_text(), text)

    def test_migrate_all_walks_the_store(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = Path(tmp) / "data" / "explanations"
            first = self._store_tree(store, "20260101-000000-one")
            second = self._store_tree(store, "20260102-000000-two")
            env = {
                "XDG_DATA_HOME": str(Path(tmp) / "data"),
                "EXPLAINCTL_T2L": str(
                    make_fake_bin(tmp, "fake-t2l", FAKE_T2L_BODY)
                ),
            }
            with patched_env(**env):
                code, result, _err = run_cli(["migrate-typst", "--all"])
            self.assertEqual(code, 0)
            self.assertEqual(
                [tree["status"] for tree in result["trees"]],
                ["migrated", "migrated"],
            )
            for root in (first, second):
                self.assertIn("$TYPST$", (root / "explanation.md").read_text())

    def test_target_and_all_are_mutually_exclusive(self):
        code, result, _err = run_cli(["migrate-typst"])
        self.assertEqual(code, 1)
        self.assertEqual(result["status"], "failed")

    def test_missing_t2l_fails_clearly(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = Path(tmp) / "data" / "explanations"
            root = self._store_tree(store, "20260101-000000-demo")
            env = {
                "XDG_DATA_HOME": str(Path(tmp) / "data"),
                "EXPLAINCTL_T2L": str(Path(tmp) / "missing-t2l"),
            }
            with patched_env(**env):
                code, result, _err = run_cli(["migrate-typst", str(root)])
            self.assertEqual(code, 1)
            self.assertEqual(result["status"], "failed")
            self.assertIn("t2l", result["message"])
            self.assertIn("$LATEX$", (root / "explanation.md").read_text())


class CliPendingBootstrapTest(unittest.TestCase):
    """`new --pending` stubs and the bootstrap-on-first-submit routing that
    backs the remote F7 flow: the stub opens in Obsidian immediately, the
    user types the question into the root document, and the first submit
    runs the bootstrap with the recorded origin binding."""

    # Bootstrap agent stub: writes the generated document (keeping the
    # question text), a child, and context notes into the staging copy
    # received via --add-dir.
    BOOTSTRAP_BODY = """
import json, os, sys
argv = sys.argv[1:]
staging = argv[argv.index("--add-dir") + 1]
assert "--fork-session" in argv
assert "--resume" in argv
prompt = argv[argv.index("-p") + 1]
with open(os.path.join(staging, "explanation.md")) as fh:
    question_doc = fh.read()
with open(os.path.join(staging, "explanation.md"), "w") as fh:
    fh.write("# Real Title\\n\\n" + question_doc + "\\nAnswer: $LATEX$\\n")
os.makedirs(os.path.join(staging, "children"), exist_ok=True)
with open(os.path.join(staging, "children", "proof.md"), "w") as fh:
    fh.write("# Proof\\n\\n$$LATEX$$\\n")
with open(os.path.join(staging, ".context.md"), "w") as fh:
    fh.write("context notes\\n")
print(json.dumps({"session_id": "boot-42", "result": "done"}))
"""

    # Same, but clobbers the LIVE root document mid-run, the way a laptop
    # rsync push of continued typing would.
    CONFLICT_BODY = BOOTSTRAP_BODY.replace(
        'print(json.dumps({"session_id": "boot-42", "result": "done"}))',
        """
root = os.path.dirname(staging)
with open(os.path.join(root, "explanation.md"), "a") as fh:
    fh.write("\\nstill typing\\n")
print(json.dumps({"session_id": "boot-42", "result": "done"}))
""",
    )

    def _env(self, tmp, agent_body):
        templates = Path(tmp) / "templates"
        templates.mkdir(exist_ok=True)
        (templates / "bootstrap.md").write_text(
            "Question: {{question}}\nWrite {{root_document}}\n"
        )
        return {
            "XDG_DATA_HOME": str(Path(tmp) / "data"),
            "EXPLAINCTL_TEMPLATES": str(templates),
            "EXPLAINCTL_CLAUDE_BIN": str(
                make_fake_bin(tmp, "fake-claude", agent_body)
            ),
            "EXPLAINCTL_T2L": str(make_fake_bin(tmp, "fake-t2l", FAKE_T2L_BODY)),
        }

    def _pending_root(self, tmp):
        origin_cwd = Path(tmp) / "the-project"
        origin_cwd.mkdir(exist_ok=True)
        code, result, _err = run_cli(
            [
                "new",
                "--pending",
                "--session-id",
                "origin-777",
                "--cwd",
                str(origin_cwd),
                "--launcher",
                "claude",
                "--no-open",
            ]
        )
        self.assertEqual(code, 0, msg=repr(result))
        return Path(result["root"]), result

    def test_new_pending_creates_stub_without_claude(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = self._env(tmp, "raise SystemExit('claude must not run')")
            # Even the fake claude must never be invoked for the stub.
            env["EXPLAINCTL_CLAUDE_BIN"] = str(Path(tmp) / "missing-claude")
            with patched_env(**env):
                root, result = self._pending_root(tmp)
            self.assertTrue(result["pending"])
            self.assertEqual(result["origin_session_id"], "origin-777")
            # Directory slug and H1 both carry the origin project identity.
            self.assertIn("-explain-the-project", root.name)
            text = (root / "explanation.md").read_text()
            self.assertIn("# Explanation: the-project", text)
            self.assertIn(cli.PENDING_INVITE, text)
            metadata = core.read_metadata(root)
            self.assertEqual(metadata["status"], "pending")
            self.assertEqual(metadata["origin"]["session_id"], "origin-777")
            locked, _ = core.TreeLock.probe(root)
            self.assertFalse(locked)

    def test_pending_and_question_are_mutually_exclusive(self):
        code, result, _err = run_cli(
            ["new", "--pending", "--question", "q", "--no-open"]
        )
        self.assertEqual(code, 1)
        self.assertIn("mutually exclusive", result["message"])

    def test_submit_without_question_fails_and_stays_pending(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patched_env(**self._env(tmp, self.BOOTSTRAP_BODY)):
                root, _ = self._pending_root(tmp)
                document = root / "explanation.md"
                code, result, _err = run_cli(["submit", str(document)])
            self.assertEqual(code, 1)
            self.assertIn("no question yet", result["message"])
            self.assertEqual(core.read_metadata(root)["status"], "pending")

    def test_submit_bootstraps_pending_tree(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patched_env(**self._env(tmp, self.BOOTSTRAP_BODY)):
                root, _ = self._pending_root(tmp)
                document = root / "explanation.md"
                # The user replaced the invitation with their question; the
                # heading stays. Their own math is already Typst.
                document.write_text(
                    "# Explanation: the-project\n\n"
                    "Why does $TYPST$ stay untouched here?\n"
                )
                code, result, _err = run_cli(["submit", str(document)])
            self.assertEqual(code, 0, msg=repr(result))
            self.assertEqual(result["status"], "updated")
            self.assertTrue(result["bootstrap"])
            self.assertEqual(result["session_id"], "boot-42")
            self.assertEqual(result["focus"], str(document))
            self.assertEqual(result["resolved_question_ids"], [])
            # .context.md was committed but never reported: the laptop opens
            # every `created` path.
            child = root / "children" / "proof.md"
            self.assertEqual(result["created"], [str(child)])
            self.assertTrue((root / ".context.md").is_file())
            text = document.read_text()
            # The stub furniture became the agent's document; the user's
            # question survived verbatim (unchanged region, so its math was
            # not re-run through t2l) while the agent's LaTeX was converted.
            self.assertIn("# Real Title", text)
            self.assertIn("Why does $TYPST$ stay untouched here?", text)
            self.assertIn("Answer: $TYPST$", text)
            self.assertEqual(child.read_text(), "# Proof\n\n$$TYPST$$\n")
            metadata = core.read_metadata(root)
            self.assertEqual(metadata["status"], "ready")
            self.assertEqual(metadata["coordinator_session_id"], "boot-42")
            self.assertEqual(metadata["math_syntax"], "typst")
            self.assertIn("Why does", metadata["question"])
            self.assertEqual(list(root.glob(".submit-*")), [])
            locked, _ = core.TreeLock.probe(root)
            self.assertFalse(locked)
            # The tree is a normal ready tree now: a second submit with no
            # open question blocks takes the ordinary path.
            with patched_env(**self._env(tmp, self.BOOTSTRAP_BODY)):
                code, result, _err = run_cli(["submit", str(document)])
            self.assertEqual(code, 0)
            self.assertEqual(result["status"], "no_questions")

    def test_bootstrap_conflict_preserves_live_document(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patched_env(**self._env(tmp, self.CONFLICT_BODY)):
                root, _ = self._pending_root(tmp)
                document = root / "explanation.md"
                document.write_text("The question\n")
                code, result, _err = run_cli(["submit", str(document)])
            self.assertEqual(code, 1)
            self.assertEqual(result["status"], "conflict")
            self.assertEqual(result["conflicting_files"], ["explanation.md"])
            text = document.read_text()
            self.assertIn("still typing", text)
            self.assertNotIn("# Real Title", text)
            self.assertTrue(Path(result["staged"]).is_dir())
            # Still pending: the next submit retries the bootstrap.
            self.assertEqual(core.read_metadata(root)["status"], "pending")
            locked, _ = core.TreeLock.probe(root)
            self.assertFalse(locked)

    def test_bootstrap_failure_stays_pending_for_retry(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patched_env(**self._env(tmp, "import sys\nsys.exit(3)\n")):
                root, _ = self._pending_root(tmp)
                document = root / "explanation.md"
                document.write_text("The question\n")
                code, result, _err = run_cli(["submit", str(document)])
            self.assertEqual(code, 1)
            self.assertEqual(result["status"], "failed")
            metadata = core.read_metadata(root)
            self.assertEqual(metadata["status"], "pending")
            self.assertIn("error", metadata)
            self.assertEqual(document.read_text(), "The question\n")
            locked, _ = core.TreeLock.probe(root)
            self.assertFalse(locked)

    def test_sync_refuses_pending_tree(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patched_env(**self._env(tmp, self.BOOTSTRAP_BODY)):
                root, _ = self._pending_root(tmp)
                code, result, _err = run_cli(
                    ["sync", str(root), "--session-id", "s", "--cwd", tmp]
                )
            self.assertEqual(code, 1)
            self.assertIn("pending bootstrap", result["message"])


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
    fh.write("\\nMath: $LATEX$\\n")
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
                "EXPLAINCTL_T2L": str(make_fake_bin(tmp, "fake-t2l", FAKE_T2L_BODY)),
            }
            with patched_env(**environ):
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
            # The bootstrap agent's LaTeX math was deterministically
            # converted to Typst before the tree went live.
            self.assertIn("Math: $TYPST$", (root / "explanation.md").read_text())
            metadata = core.read_metadata(root)
            self.assertEqual(metadata["status"], "ready")
            self.assertEqual(metadata["math_syntax"], "typst")
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
