"""explainctl command-line interface.

Every subcommand prints one JSON result object on stdout and a concise
human-readable line on stderr. Exit codes: 0 success, 1 failure, 2 usage,
75 (EX_TEMPFAIL) when the tree lock is busy.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

from . import core


class CommandError(Exception):
    """A failure with a JSON payload; raising it emits and exits 1."""

    def __init__(self, message: str, **fields):
        super().__init__(message)
        self.fields = fields


# ---------------------------------------------------------------------------
# Emission


def _emit(result: dict, human: str, code: int = 0) -> int:
    print(json.dumps(result, indent=2))
    print(human, file=sys.stderr)
    return code


def _busy(error: core.ExplainBusy, submitted: str | None) -> int:
    result = {
        "status": "busy",
        "message": "An explanation update is already running.",
        "submitted": submitted,
        "active_pid": error.owner.get("pid"),
    }
    return _emit(result, "busy: an explanation update is already running", core.EX_BUSY)


# ---------------------------------------------------------------------------
# Claude invocation


def _launcher_command(origin: dict) -> tuple[list[str], dict]:
    """The recorded launcher reconstructs its own environment (gateway,
    tokens, proxies); nothing sensitive is stored here. An unknown profile is
    resumed with the plain launcher plus its recorded CLAUDE_CONFIG_DIR."""
    env = dict(os.environ)
    override = env.get("EXPLAINCTL_CLAUDE_BIN")  # test seam
    if override:
        return [override], env
    launcher = origin.get("launcher")
    if launcher in core.KNOWN_LAUNCHERS:
        return [launcher], env
    if origin.get("config_dir"):
        env["CLAUDE_CONFIG_DIR"] = origin["config_dir"]
    return ["claude"], env


def parse_claude_output(stdout: str) -> dict:
    """`claude -p --output-format json` prints one JSON object; tolerate
    stray non-JSON lines around it."""
    try:
        data = json.loads(stdout)
        if isinstance(data, dict):
            return data
    except ValueError:
        pass
    for line in reversed(stdout.splitlines()):
        line = line.strip()
        if line.startswith("{"):
            try:
                data = json.loads(line)
                if isinstance(data, dict):
                    return data
            except ValueError:
                continue
    raise CommandError("could not parse Claude JSON output", stdout_tail=stdout[-2000:])


def run_claude(
    origin: dict,
    prompt: str,
    resume_session_id: str,
    root: Path,
    fork: bool,
) -> dict:
    """One-shot resume in the origin working directory. The prompt precedes
    the variadic/optional flags (--add-dir) so nothing swallows it; see
    docs/session-handoff.md for the measured flag-order trap."""
    command, env = _launcher_command(origin)
    command += ["-p", prompt, "--resume", resume_session_id]
    if fork:
        command.append("--fork-session")
    command += ["--output-format", "json", "--add-dir", str(root)]
    cwd = origin["cwd"]
    if not Path(cwd).is_dir():
        raise CommandError("origin working directory does not exist", cwd=cwd)
    try:
        completed = subprocess.run(
            command, cwd=cwd, env=env, capture_output=True, text=True, check=False
        )
    except FileNotFoundError:
        raise CommandError(
            "launcher not found on PATH", launcher=command[0]
        ) from None
    if completed.returncode != 0:
        raise CommandError(
            "Claude invocation failed",
            launcher=command[0],
            exit_code=completed.returncode,
            stderr_tail=completed.stderr[-2000:],
        )
    return parse_claude_output(completed.stdout)


def _session_id_from(result: dict) -> str:
    session_id = result.get("session_id") or result.get("sessionId")
    if not session_id:
        raise CommandError(
            "Claude result carries no session_id", result_keys=sorted(result)
        )
    return str(session_id)


# ---------------------------------------------------------------------------
# Workspace window


def launch_workspace(root: Path, focus: Path, slug: str) -> bool:
    if shutil.which("kitty") is None:
        return False
    subprocess.Popen(
        [
            "kitty",
            "--detach",
            "--class",
            "explanation-nvim",
            "--title",
            f"Explanation: {slug}",
            "nvim",
            str(focus),
        ],
        cwd=str(root),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return True


# ---------------------------------------------------------------------------
# Root resolution helpers


def _require_root(target: str) -> Path:
    root = core.resolve_root(Path(target))
    if root is None:
        raise CommandError(
            "no .explain.json found walking upward", target=str(Path(target).resolve())
        )
    return root


def _resolve_target_root(target: str, environ=None) -> Path:
    """A path (file or directory) inside a tree, or a slug fragment matched
    against the explanation store."""
    path = Path(target).expanduser()
    if path.exists():
        return _require_root(str(path))
    store = core.data_dir(environ)
    matches = [
        entry
        for entry in sorted(store.iterdir() if store.is_dir() else [])
        if entry.is_dir()
        and (entry / core.METADATA_NAME).is_file()
        and target in entry.name
    ]
    if len(matches) == 1:
        return matches[0]
    if not matches:
        raise CommandError("no explanation matches", target=target, store=str(store))
    raise CommandError(
        "multiple explanations match",
        target=target,
        matches=[str(match) for match in matches],
    )


def _question_digest(questions: list[core.Question], root: Path) -> str:
    lines = []
    for question in questions:
        location = (
            str(question.file.relative_to(root)) if question.file else "unknown"
        )
        lines.append(f'- id="{question.id}" file="{location}" line={question.line}')
        for text_line in (question.text or "(empty question)").splitlines():
            lines.append(f"  {text_line}")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Subcommands


def cmd_new(args) -> int:
    question = args.question.strip()
    if not question:
        raise CommandError("--question must not be empty")
    origin = core.resolve_origin(args.session_id, args.cwd, args.launcher)
    if not origin["session_id"]:
        raise CommandError(
            "no origin session: pass --session-id or run inside a Claude Code "
            "Bash tool where CLAUDE_CODE_SESSION_ID is set"
        )

    store = core.data_dir()
    root = core.new_root(store, question)
    slug = root.name
    lock = core.TreeLock(root)
    try:
        lock.acquire("new")
    except core.ExplainBusy as error:
        return _busy(error, None)
    opened = False
    try:
        metadata = core.new_metadata(slug, question, origin)
        core.write_metadata(root, metadata)

        staging = root / core.STAGING_DIR
        staging.mkdir()
        try:
            prompt = core.render_template(
                core.load_template("bootstrap.md", origin),
                {
                    "question": question,
                    "explanation_root": root,
                    "staging_dir": staging,
                    "root_document": staging / core.ROOT_DOCUMENT,
                    "context_file": staging / core.CONTEXT_NAME,
                    "children_dir": staging / core.CHILDREN_DIR,
                    "origin_cwd": origin["cwd"],
                },
            )
            result = run_claude(origin, prompt, origin["session_id"], root, fork=True)
            coordinator = _session_id_from(result)
            staged_document = staging / core.ROOT_DOCUMENT
            if not staged_document.is_file() or not staged_document.stat().st_size:
                raise CommandError(
                    "fork produced no explanation document",
                    expected=str(staged_document),
                )
        except (CommandError, FileNotFoundError) as error:
            metadata["status"] = "failed"
            metadata["updated_at"] = core.iso_now()
            metadata["error"] = str(error)
            core.write_metadata(root, metadata)
            fields = error.fields if isinstance(error, CommandError) else {}
            raise CommandError(str(error), root=str(root), **fields) from None

        # Staged tree validated: move it into place, then mark ready.
        for entry in sorted(staging.iterdir()):
            os.replace(entry, root / entry.name)
        os.rmdir(staging)

        metadata["coordinator_session_id"] = coordinator
        metadata["status"] = "ready"
        metadata["updated_at"] = core.iso_now()
        metadata.pop("error", None)
        core.write_metadata(root, metadata)
    finally:
        # The renderer must never open a half-generated tree: the lock is
        # held from before "creating" until after "ready", and Kitty is
        # launched only after release.
        lock.release()

    focus = core.root_document(root, metadata)
    if not args.no_open:
        opened = launch_workspace(root, focus, slug)
    result = {
        "status": "created",
        "root": str(root),
        "focus": str(focus),
        "session_id": coordinator,
        "origin_session_id": origin["session_id"],
        "launcher": origin["launcher"],
        "opened": opened,
    }
    human = f"created {root} (coordinator {coordinator})"
    if not args.no_open and not opened:
        result["warning"] = "kitty not found on PATH; workspace not opened"
        human += "; kitty not found, workspace not opened"
    return _emit(result, human)


def cmd_submit(args) -> int:
    submitted = Path(args.file).resolve()
    root = _require_root(str(submitted))
    lock = core.TreeLock(root)
    try:
        lock.acquire("submit", str(submitted))
    except core.ExplainBusy as error:
        return _busy(error, str(submitted))
    with lock:
        metadata = core.read_metadata(root)
        if metadata.get("status") != "ready":
            raise CommandError(
                "explanation is not ready",
                root=str(root),
                metadata_status=metadata.get("status"),
                hint="run `explainctl sync` to attach a new coordinator",
            )
        coordinator = metadata.get("coordinator_session_id")
        if not coordinator:
            raise CommandError(
                "no coordinator session recorded; run `explainctl sync`",
                root=str(root),
            )
        questions = core.open_questions_in_tree(root)
        if not questions:
            return _emit(
                {
                    "status": "no_questions",
                    "root": str(root),
                    "submitted": str(submitted),
                },
                "no open questions; nothing submitted",
            )

        origin = metadata.get("origin") or {}
        prompt = core.render_template(
            core.load_template("update.md", origin),
            {
                "explanation_root": root,
                "root_document": core.root_document(root, metadata),
                "context_file": root / core.CONTEXT_NAME,
                "children_dir": root / core.CHILDREN_DIR,
                "questions": _question_digest(questions, root),
                "submitted": submitted,
            },
        )
        before = core.hash_tree(root)
        open_before = {question.id for question in questions}
        snapshot = core.snapshot_tree(root)
        try:
            run_claude(origin, prompt, coordinator, root, fork=False)
        except CommandError as error:
            restore = core.restore_snapshot(root, snapshot)
            core.discard_snapshot(snapshot)
            raise CommandError(
                str(error),
                root=str(root),
                submitted=str(submitted),
                restored=True,
                quarantine_dir=restore["quarantine_dir"],
                **error.fields,
            ) from None
        core.discard_snapshot(snapshot)

        after = core.hash_tree(root)
        updated, created = core.diff_hashes(before, after)
        open_after = {question.id for question in core.open_questions_in_tree(root)}
        resolved = sorted(open_before - open_after)
        created_absolute = [str(root / path) for path in created]
        if len(created_absolute) == 1:
            focus = created_absolute[0]
        else:
            focus = str(submitted)
        metadata["updated_at"] = core.iso_now()
        core.write_metadata(root, metadata)
        result = {
            "status": "updated",
            "root": str(root),
            "submitted": str(submitted),
            "updated": [str(root / path) for path in updated],
            "created": created_absolute,
            "focus": focus,
            "resolved_question_ids": resolved,
        }
        return _emit(
            result,
            "updated %d file(s), created %d, resolved %d question(s)"
            % (len(updated), len(created), len(resolved)),
        )


def cmd_sync(args) -> int:
    root = _require_root(args.target)
    origin = core.resolve_origin(args.session_id, args.cwd, args.launcher)
    if not origin["session_id"]:
        raise CommandError(
            "no origin session: pass --session-id or run inside a Claude Code "
            "Bash tool where CLAUDE_CODE_SESSION_ID is set"
        )
    lock = core.TreeLock(root)
    try:
        lock.acquire("sync")
    except core.ExplainBusy as error:
        return _busy(error, None)
    with lock:
        metadata = core.read_metadata(root)
        previous = metadata.get("coordinator_session_id")
        prompt = core.render_template(
            core.load_template("sync.md", origin),
            {
                "explanation_root": root,
                "root_document": core.root_document(root, metadata),
                "context_file": root / core.CONTEXT_NAME,
                "children_dir": root / core.CHILDREN_DIR,
            },
        )
        result = run_claude(origin, prompt, origin["session_id"], root, fork=True)
        coordinator = _session_id_from(result)
        metadata["coordinator_session_id"] = coordinator
        metadata["origin"] = origin
        metadata["status"] = "ready"
        metadata["last_sync_at"] = core.iso_now()
        metadata["updated_at"] = metadata["last_sync_at"]
        metadata.pop("error", None)
        core.write_metadata(root, metadata)
    return _emit(
        {
            "status": "synced",
            "root": str(root),
            "session_id": coordinator,
            "previous_session_id": previous,
            "launcher": origin["launcher"],
        },
        f"synced {root} onto session {origin['session_id']} (coordinator {coordinator})",
    )


def cmd_status(args) -> int:
    root = _resolve_target_root(args.target)
    metadata = core.read_metadata(root)
    locked, owner = core.TreeLock.probe(root)
    result = {
        "status": metadata.get("status"),
        "root": str(root),
        "root_document": str(core.root_document(root, metadata)),
        "locked": locked,
        "lock_owner": owner if locked else None,
        "open_questions": len(core.open_questions_in_tree(root)),
        "coordinator_session_id": metadata.get("coordinator_session_id"),
        "origin": metadata.get("origin"),
        "created_at": metadata.get("created_at"),
        "updated_at": metadata.get("updated_at"),
        "last_sync_at": metadata.get("last_sync_at"),
    }
    busy_note = " (update running)" if locked else ""
    return _emit(result, f"{root}: {result['status']}{busy_note}")


def cmd_list(_args) -> int:
    store = core.data_dir()
    explanations = []
    if store.is_dir():
        for entry in sorted(store.iterdir()):
            if not (entry / core.METADATA_NAME).is_file():
                continue
            try:
                metadata = core.read_metadata(entry)
            except (OSError, ValueError):
                metadata = {}
            explanations.append(
                {
                    "root": str(entry),
                    "slug": metadata.get("slug", entry.name),
                    "status": metadata.get("status"),
                    "question": metadata.get("question"),
                    "created_at": metadata.get("created_at"),
                    "updated_at": metadata.get("updated_at"),
                    "launcher": (metadata.get("origin") or {}).get("launcher"),
                }
            )
    explanations.sort(key=lambda entry: entry.get("created_at") or "", reverse=True)
    return _emit(
        {"status": "ok", "explanations": explanations},
        f"{len(explanations)} explanation(s) in {store}",
    )


def cmd_open(args) -> int:
    root = _resolve_target_root(args.target)
    metadata = core.read_metadata(root)
    focus = core.root_document(root, metadata)
    opened = launch_workspace(root, focus, metadata.get("slug", root.name))
    if not opened:
        raise CommandError("kitty not found on PATH", root=str(root))
    return _emit(
        {"status": "opened", "root": str(root), "focus": str(focus)},
        f"opened {focus}",
    )


def cmd_doctor(_args) -> int:
    checks = []

    def check(name: str, ok: bool, detail: str, required: bool = True) -> None:
        checks.append({"name": name, "ok": ok, "detail": detail, "required": required})

    store = core.data_dir()
    try:
        store.mkdir(parents=True, exist_ok=True)
        probe = core.TreeLock(store)
        probe.acquire("doctor")
        probe.release()
        (store / core.LOCK_NAME).unlink()
        check("data-dir", True, str(store))
    except OSError as error:
        check("data-dir", False, f"{store}: {error}")

    for launcher, required in (("claude", True), ("claude-gpt56", False)):
        found = shutil.which(launcher)
        check(
            f"launcher-{launcher}",
            found is not None,
            found or "not on PATH",
            required,
        )
    for tool in ("nvim", "kitty"):
        found = shutil.which(tool)
        check(tool, found is not None, found or "not on PATH")

    for launcher in core.KNOWN_LAUNCHERS:
        origin = {"launcher": launcher, "config_dir": None}
        for name in ("bootstrap.md", "update.md", "sync.md"):
            try:
                core.load_template(name, origin)
                check(f"template-{launcher}-{name}", True, name, launcher == "claude")
            except FileNotFoundError as error:
                check(
                    f"template-{launcher}-{name}",
                    False,
                    str(error),
                    launcher == "claude",
                )

    session = os.environ.get("CLAUDE_CODE_SESSION_ID")
    check(
        "claude-session-env",
        True,
        session or "CLAUDE_CODE_SESSION_ID not set (fine outside a Claude Bash tool)",
        False,
    )

    healthy = all(entry["ok"] for entry in checks if entry["required"])
    failures = [entry["name"] for entry in checks if entry["required"] and not entry["ok"]]
    return _emit(
        {"status": "ok" if healthy else "error", "checks": checks},
        "doctor: ok" if healthy else "doctor: failing checks: " + ", ".join(failures),
        0 if healthy else 1,
    )


# ---------------------------------------------------------------------------
# Entry point


def _add_origin_flags(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--session-id",
        help="origin Claude session ID (default: $CLAUDE_CODE_SESSION_ID)",
    )
    parser.add_argument(
        "--cwd", help="origin project working directory (default: current directory)"
    )
    parser.add_argument(
        "--launcher",
        choices=list(core.KNOWN_LAUNCHERS),
        help="Claude launcher to record and resume with (default: inferred "
        "from CLAUDE_CONFIG_DIR)",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="explainctl",
        description="Forked Claude explanation workspaces: persistent Markdown "
        "trees updated by a dormant forked session.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="accepted for compatibility; JSON is always printed on stdout",
    )
    commands = parser.add_subparsers(dest="command", required=True)

    new = commands.add_parser("new", help="fork the origin session into a new explanation tree")
    new.add_argument("--question", required=True, help="what needs explaining")
    _add_origin_flags(new)
    new.add_argument(
        "--no-open",
        action="store_true",
        help="do not launch the Kitty/Neovim workspace; emit paths only",
    )
    new.set_defaults(func=cmd_new)

    submit = commands.add_parser("submit", help="process open question blocks in a tree")
    submit.add_argument("file", help="Markdown file inside the explanation tree")
    submit.set_defaults(func=cmd_submit)

    sync = commands.add_parser(
        "sync", help="rebase an existing tree onto the current main session"
    )
    sync.add_argument("target", help="explanation root or a file inside it")
    _add_origin_flags(sync)
    sync.set_defaults(func=cmd_sync)

    status = commands.add_parser("status", help="tree status, lock state, open questions")
    status.add_argument("target", nargs="?", default=".", help="path or slug fragment")
    status.set_defaults(func=cmd_status)

    listing = commands.add_parser("list", help="list explanation trees")
    listing.set_defaults(func=cmd_list)

    opener = commands.add_parser("open", help="reopen a tree in the Kitty/Neovim workspace")
    opener.add_argument("target", help="path or slug fragment")
    opener.set_defaults(func=cmd_open)

    doctor = commands.add_parser("doctor", help="environment checks")
    doctor.set_defaults(func=cmd_doctor)
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except CommandError as error:
        result = {"status": "failed", "message": str(error)}
        result.update(error.fields)
        return _emit(result, f"error: {error}", 1)
    except FileNotFoundError as error:
        return _emit({"status": "failed", "message": str(error)}, f"error: {error}", 1)
    except core.ExplainBusy as error:
        return _busy(error, None)
