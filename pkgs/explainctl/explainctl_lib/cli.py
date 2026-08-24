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

from . import core, typst_math


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


def _convert_staged_to_typst(files: list[Path]) -> tuple[bool, list[dict]]:
    """Deterministic post-agent step: agents write LaTeX math, the tree is
    canonically Typst. Converts the given files in place and returns
    (converted, warnings); a missing t2l degrades to no conversion so the
    agent's output is never lost."""
    if not typst_math.t2l_available():
        return False, [{"detail": "t2l not found on PATH; math left as LaTeX"}]
    warnings: list[dict] = []
    for path in files:
        text = path.read_text(encoding="utf-8")
        converted, segment_warnings = typst_math.convert_markdown(text)
        warnings.extend(warning.as_dict() for warning in segment_warnings)
        if converted != text:
            path.write_text(converted, encoding="utf-8")
    return True, warnings


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

# First line of a pending stub's root document body: the remote F7 flow opens
# the stub in Obsidian and the user replaces this invitation with the actual
# question, then submits.
PENDING_INVITE = "<!-- Type your question here, then run the submit command. -->"


def _origin_label(origin: dict) -> str:
    """Identify the origin project the way the Herdr tab label does
    (scripts/herdr-explain-current): basename of the origin cwd, truncated."""
    base = os.path.basename(os.path.normpath(origin.get("cwd") or ""))
    if base in ("", "/", "."):
        return ""
    if len(base) > 24:
        base = base[:23] + "…"
    return base


def _pending_question(text: str) -> str:
    """The user's question is the pending root document minus the stub
    furniture: the invitation comment and the generated `# Explanation:`
    heading. Everything else they typed is the question, verbatim."""
    lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped == PENDING_INVITE:
            continue
        if stripped == "# Explanation" or stripped.startswith("# Explanation:"):
            continue
        lines.append(line)
    return "\n".join(lines).strip()


def _require_origin(args) -> dict:
    origin = core.resolve_origin(args.session_id, args.cwd, args.launcher)
    if not origin["session_id"]:
        raise CommandError(
            "no origin session: pass --session-id or run inside a Claude Code "
            "Bash tool where CLAUDE_CODE_SESSION_ID is set"
        )
    return origin


def _existing_pending(store: Path, origin: dict) -> tuple[Path, dict] | None:
    """The newest tree still pending bootstrap that records the same origin
    session, if any: a repeated F7 press must reopen the stub the first press
    minted, not create another one."""
    candidates = []
    for entry in sorted(store.iterdir() if store.is_dir() else []):
        if not entry.is_dir() or not (entry / core.METADATA_NAME).is_file():
            continue
        try:
            metadata = core.read_metadata(entry)
        except (OSError, ValueError):
            continue
        if metadata.get("status") != "pending":
            continue
        if (metadata.get("origin") or {}).get("session_id") != origin["session_id"]:
            continue
        candidates.append((metadata.get("created_at") or "", entry, metadata))
    if not candidates:
        return None
    _, root, metadata = max(candidates, key=lambda item: item[0])
    return root, metadata


def _create_pending(args) -> int:
    """`new --pending`: record the origin binding and hand back an openable
    stub immediately — no Claude run. The first `submit` on the tree reads
    the question out of the root document and runs the bootstrap. Idempotent
    per origin session: an existing pending stub is returned instead of a
    new one, so the caller just re-dispatches the same note."""
    origin = _require_origin(args)
    store = core.data_dir()
    existing = _existing_pending(store, origin)
    if existing is not None:
        root, metadata = existing
        result = {
            "status": "existing",
            "pending": True,
            "root": str(root),
            "focus": str(core.root_document(root, metadata)),
            "origin_session_id": origin["session_id"],
            "launcher": origin["launcher"],
            "opened": False,
        }
        return _emit(
            result, "pending tree %s already exists for this session" % root
        )
    label = _origin_label(origin)
    root = core.new_root(store, "explain %s" % (label or "explanation"))
    document = root / core.ROOT_DOCUMENT
    heading = "# Explanation: %s" % label if label else "# Explanation"
    document.write_text(
        "%s\n\n%s\n" % (heading, PENDING_INVITE), encoding="utf-8"
    )
    metadata = core.new_metadata(root.name, "", origin)
    metadata["status"] = "pending"
    core.write_metadata(root, metadata)
    result = {
        "status": "created",
        "pending": True,
        "root": str(root),
        "focus": str(document),
        "origin_session_id": origin["session_id"],
        "launcher": origin["launcher"],
        "opened": False,
    }
    return _emit(result, "created pending tree %s; the first submit bootstraps it" % root)


def cmd_new(args) -> int:
    if args.pending and args.question:
        raise CommandError("--pending and --question are mutually exclusive")
    if args.pending:
        return _create_pending(args)
    question = (args.question or "").strip()
    if not question:
        raise CommandError("--question must not be empty")
    origin = _require_origin(args)

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

        # Deterministic post-agent step: the bootstrap agent wrote LaTeX
        # math; the canonical tree is Typst. Everything in staging is new, so
        # every file is converted whole.
        converted, conversion_warnings = _convert_staged_to_typst(
            core.staged_targets(staging)
        )
        if converted:
            metadata[typst_math.MATH_SYNTAX_KEY] = typst_math.MATH_SYNTAX_TYPST

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
    if conversion_warnings:
        result["conversion_warnings"] = conversion_warnings
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
        if metadata.get("status") == "pending":
            return _bootstrap_submit(root, submitted, metadata)
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
        # Conflict protocol: hash the live tree, hand the agent a staged
        # copy, and only commit the staged result if the live files are still
        # exactly what was hashed. The flock serializes explainctl callers;
        # the hashes catch out-of-band writers (the laptop's rsync push).
        before = core.hash_tree(root)
        open_before = {question.id for question in questions}
        staging = core.stage_tree(root)
        root_document_rel = metadata.get("root_document") or core.ROOT_DOCUMENT
        prompt = core.render_template(
            core.load_template("update.md", origin),
            {
                "explanation_root": staging,
                "root_document": staging / root_document_rel,
                "context_file": staging / core.CONTEXT_NAME,
                "children_dir": staging / core.CHILDREN_DIR,
                "questions": _question_digest(questions, root),
                "submitted": staging / submitted.relative_to(root),
            },
        )
        try:
            # --add-dir grants the fork the staging copy only: even a
            # confused agent reusing live paths from earlier turns cannot
            # bypass the conflict check.
            run_claude(origin, prompt, coordinator, staging, fork=False)
        except CommandError as error:
            # Live tree untouched; the staged partial result is kept (dot
            # prefix hides it from tree scans) for inspection.
            raise CommandError(
                str(error),
                root=str(root),
                submitted=str(submitted),
                staged=str(staging),
                **error.fields,
            ) from None

        live_now = core.hash_tree(root)
        if live_now != before:
            conflicting = sorted(
                set(path for path in live_now if before.get(path) != live_now[path])
                | (set(before) - set(live_now))
            )
            return _emit(
                {
                    "status": "conflict",
                    "root": str(root),
                    "submitted": str(submitted),
                    "staged": str(staging),
                    "conflicting_files": conflicting,
                    "message": "tree changed while the update ran; "
                    "staged result preserved, live files untouched",
                },
                "conflict: %d live file(s) changed during the update; "
                "staged result kept at %s" % (len(conflicting), staging),
                1,
            )

        # Deterministic post-agent step: convert the LaTeX math the agent
        # just wrote to Typst — only in regions the agent changed, because
        # pre-existing math is already Typst and t2l must not see it twice.
        convert = core.tree_is_typst(metadata)
        conversion_warnings: list[dict] = []
        if convert and not typst_math.t2l_available():
            convert = False
            conversion_warnings.append(
                {"detail": "t2l not found on PATH; new math left as LaTeX"}
            )
        updated, created = [], []
        for staged in core.staged_targets(staging):
            relative = staged.relative_to(staging)
            live = root / relative
            after_text = staged.read_text(encoding="utf-8")
            before_text = (
                live.read_text(encoding="utf-8") if live.is_file() else None
            )
            if before_text == after_text:
                continue
            if convert:
                after_text, segment_warnings = typst_math.convert_changed(
                    before_text, after_text
                )
                conversion_warnings.extend(w.as_dict() for w in segment_warnings)
                staged.write_text(after_text, encoding="utf-8")
            (created if before_text is None else updated).append(relative)

        for relative in updated + created:
            destination = root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            os.replace(staging / relative, destination)
        core.discard_staging(staging)

        open_after = {question.id for question in core.open_questions_in_tree(root)}
        resolved = sorted(open_before - open_after)
        created_absolute = [str(root / path) for path in sorted(created)]
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
            "updated": [str(root / path) for path in sorted(updated)],
            "created": created_absolute,
            "focus": focus,
            "resolved_question_ids": resolved,
        }
        if conversion_warnings:
            result["conversion_warnings"] = conversion_warnings
        return _emit(
            result,
            "updated %d file(s), created %d, resolved %d question(s)"
            % (len(updated), len(created), len(resolved)),
        )


def _bootstrap_submit(root: Path, submitted: Path, metadata: dict) -> int:
    """First submit on a `new --pending` stub (the caller holds the tree
    lock): the root document's current content is the initial question. Run
    the bootstrap fork that `new --question` would have run, then commit the
    generated tree under the same staging/conflict protocol as a normal
    submit, so the document the user typed into is never clobbered if they
    kept editing while the bootstrap ran."""
    origin = metadata.get("origin") or {}
    if not origin.get("session_id"):
        raise CommandError(
            "pending tree records no origin session", root=str(root)
        )
    document = core.root_document(root, metadata)
    question = _pending_question(
        document.read_text(encoding="utf-8") if document.is_file() else ""
    )
    if not question:
        raise CommandError(
            "no question yet: type it into the root document and submit again",
            root=str(root),
            focus=str(document),
        )

    before = core.hash_tree(root)
    staging = core.stage_tree(root)
    root_document_rel = metadata.get("root_document") or core.ROOT_DOCUMENT
    prompt = core.render_template(
        core.load_template("bootstrap.md", origin),
        {
            "question": question,
            "explanation_root": root,
            "staging_dir": staging,
            "root_document": staging / root_document_rel,
            "context_file": staging / core.CONTEXT_NAME,
            "children_dir": staging / core.CHILDREN_DIR,
            "origin_cwd": origin.get("cwd", ""),
        },
    )
    try:
        result = run_claude(
            origin, prompt, origin["session_id"], staging, fork=True
        )
        coordinator = _session_id_from(result)
        staged_document = staging / root_document_rel
        if not staged_document.is_file() or not staged_document.stat().st_size:
            raise CommandError(
                "bootstrap produced no explanation document",
                expected=str(staged_document),
            )
    except CommandError as error:
        # Status stays "pending": the question is still in the live document
        # and the next submit retries. The staged partial result is kept (dot
        # prefix hides it from tree scans) for inspection.
        metadata["error"] = str(error)
        metadata["updated_at"] = core.iso_now()
        core.write_metadata(root, metadata)
        raise CommandError(
            str(error),
            root=str(root),
            submitted=str(submitted),
            staged=str(staging),
            **error.fields,
        ) from None

    live_now = core.hash_tree(root)
    if live_now != before:
        conflicting = sorted(
            set(path for path in live_now if before.get(path) != live_now[path])
            | (set(before) - set(live_now))
        )
        return _emit(
            {
                "status": "conflict",
                "root": str(root),
                "submitted": str(submitted),
                "staged": str(staging),
                "conflicting_files": conflicting,
                "message": "tree changed while the bootstrap ran; "
                "staged result preserved, live files untouched",
            },
            "conflict: %d live file(s) changed during the bootstrap; "
            "staged result kept at %s" % (len(conflicting), staging),
            1,
        )

    # The whole staged tree is fresh agent output, so convert like `new`
    # does — but region-diffed against the live question document, so math
    # the user typed themselves is never run through t2l.
    convert = typst_math.t2l_available()
    conversion_warnings: list[dict] = []
    if not convert:
        conversion_warnings.append(
            {"detail": "t2l not found on PATH; math left as LaTeX"}
        )
    updated, created = [], []
    for staged in core.staged_targets(staging):
        relative = staged.relative_to(staging)
        live = root / relative
        after_text = staged.read_text(encoding="utf-8")
        before_text = live.read_text(encoding="utf-8") if live.is_file() else None
        if before_text == after_text:
            continue
        if convert:
            after_text, segment_warnings = typst_math.convert_changed(
                before_text, after_text
            )
            conversion_warnings.extend(w.as_dict() for w in segment_warnings)
            staged.write_text(after_text, encoding="utf-8")
        (created if before_text is None else updated).append(relative)
    for relative in updated + created:
        destination = root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        os.replace(staging / relative, destination)
    core.discard_staging(staging)

    metadata["question"] = question
    metadata["coordinator_session_id"] = coordinator
    metadata["status"] = "ready"
    if convert:
        metadata[typst_math.MATH_SYNTAX_KEY] = typst_math.MATH_SYNTAX_TYPST
    metadata["updated_at"] = core.iso_now()
    metadata.pop("error", None)
    core.write_metadata(root, metadata)

    # Hidden entries (.context.md) are committed above but stay out of the
    # result lists: the laptop's explain-sync opens every `created` path.
    def visible(paths):
        return [
            str(root / path)
            for path in sorted(paths)
            if not any(part.startswith(".") for part in path.parts)
        ]

    result = {
        "status": "updated",
        "bootstrap": True,
        "root": str(root),
        "submitted": str(submitted),
        "updated": visible(updated),
        "created": visible(created),
        "focus": str(document),
        "resolved_question_ids": [],
        "session_id": coordinator,
    }
    if conversion_warnings:
        result["conversion_warnings"] = conversion_warnings
    return _emit(
        result, "bootstrapped %s (coordinator %s)" % (root, coordinator)
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
        if metadata.get("status") == "pending":
            raise CommandError(
                "tree is pending bootstrap: submit the root document with "
                "the question first",
                root=str(root),
            )
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
        # The takeover turn only reads the tree and may refresh .context.md;
        # remember its content so any refresh gets the same deterministic
        # LaTeX -> Typst pass as submit output.
        context = root / core.CONTEXT_NAME
        context_before = (
            context.read_text(encoding="utf-8") if context.is_file() else None
        )
        result = run_claude(origin, prompt, origin["session_id"], root, fork=True)
        coordinator = _session_id_from(result)
        if (
            core.tree_is_typst(metadata)
            and typst_math.t2l_available()
            and context.is_file()
        ):
            context_after = context.read_text(encoding="utf-8")
            if context_after != context_before:
                converted, _warnings = typst_math.convert_changed(
                    context_before, context_after
                )
                if converted != context_after:
                    core.write_text_atomic(context, converted)
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


def _migrate_one_tree(root: Path) -> dict:
    """Convert one tree's LaTeX math to Typst, exactly once: the
    math_syntax marker in .explain.json makes re-runs no-ops, because t2l
    over already-Typst math would mangle it."""
    try:
        metadata = core.read_metadata(root)
    except (OSError, ValueError) as error:
        return {"root": str(root), "status": "failed", "message": str(error)}
    if core.tree_is_typst(metadata):
        return {"root": str(root), "status": "skipped", "reason": "already typst"}
    lock = core.TreeLock(root)
    try:
        lock.acquire("migrate-typst")
    except core.ExplainBusy as error:
        return {
            "root": str(root),
            "status": "busy",
            "active_pid": error.owner.get("pid"),
        }
    with lock:
        converted_files = []
        warnings: list[dict] = []
        for path in core.staged_targets(root):
            text = path.read_text(encoding="utf-8")
            converted, segment_warnings = typst_math.convert_markdown(text)
            warnings.extend(warning.as_dict() for warning in segment_warnings)
            if converted != text:
                core.write_text_atomic(path, converted)
                converted_files.append(str(path.relative_to(root)))
        metadata[typst_math.MATH_SYNTAX_KEY] = typst_math.MATH_SYNTAX_TYPST
        metadata["updated_at"] = core.iso_now()
        core.write_metadata(root, metadata)
    entry = {
        "root": str(root),
        "status": "migrated",
        "converted_files": converted_files,
    }
    if warnings:
        entry["warnings"] = warnings
    return entry


def cmd_migrate_typst(args) -> int:
    if bool(args.all) == bool(args.target):
        raise CommandError("pass exactly one of a tree target or --all")
    if not typst_math.t2l_available():
        raise CommandError("t2l not found on PATH", binary=typst_math.t2l_binary())
    if args.all:
        store = core.data_dir()
        roots = [
            entry
            for entry in sorted(store.iterdir() if store.is_dir() else [])
            if entry.is_dir() and (entry / core.METADATA_NAME).is_file()
        ]
    else:
        roots = [_resolve_target_root(args.target)]
    trees = [_migrate_one_tree(root) for root in roots]
    migrated = sum(1 for tree in trees if tree["status"] == "migrated")
    failed = [tree for tree in trees if tree["status"] in ("failed", "busy")]
    return _emit(
        {"status": "ok" if not failed else "error", "trees": trees},
        "migrated %d tree(s), skipped %d, failed %d"
        % (migrated, sum(1 for t in trees if t["status"] == "skipped"), len(failed)),
        0 if not failed else 1,
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
        "math_syntax": metadata.get(typst_math.MATH_SYNTAX_KEY),
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
    # A parent-parser optional is never matched once argparse has dispatched
    # into a subparser, so the compat flag must be inherited by every
    # subcommand or `explainctl submit --json f` exits 2 (the F7 regression).
    compat = argparse.ArgumentParser(add_help=False)
    compat.add_argument(
        "--json",
        action="store_true",
        help="accepted for compatibility; JSON is always printed on stdout",
    )
    parser = argparse.ArgumentParser(
        prog="explainctl",
        parents=[compat],
        description="Forked Claude explanation workspaces: persistent Markdown "
        "trees updated by a dormant forked session.",
    )
    commands = parser.add_subparsers(dest="command", required=True)

    new = commands.add_parser(
        "new",
        parents=[compat],
        help="fork the origin session into a new explanation tree",
    )
    new.add_argument("--question", help="what needs explaining")
    new.add_argument(
        "--pending",
        action="store_true",
        help="create an openable stub without running Claude; the first "
        "submit reads the question out of the root document and bootstraps",
    )
    _add_origin_flags(new)
    new.add_argument(
        "--no-open",
        action="store_true",
        help="do not launch the Kitty/Neovim workspace; emit paths only",
    )
    new.set_defaults(func=cmd_new)

    submit = commands.add_parser(
        "submit", parents=[compat], help="process open question blocks in a tree"
    )
    submit.add_argument("file", help="Markdown file inside the explanation tree")
    submit.set_defaults(func=cmd_submit)

    sync = commands.add_parser(
        "sync",
        parents=[compat],
        help="rebase an existing tree onto the current main session",
    )
    sync.add_argument("target", help="explanation root or a file inside it")
    _add_origin_flags(sync)
    sync.set_defaults(func=cmd_sync)

    migrate = commands.add_parser(
        "migrate-typst",
        parents=[compat],
        help="one-time conversion of a tree's LaTeX math to Typst",
    )
    migrate.add_argument(
        "target", nargs="?", help="explanation root, file inside it, or slug fragment"
    )
    migrate.add_argument(
        "--all", action="store_true", help="migrate every tree in the store"
    )
    migrate.set_defaults(func=cmd_migrate_typst)

    status = commands.add_parser(
        "status", parents=[compat], help="tree status, lock state, open questions"
    )
    status.add_argument("target", nargs="?", default=".", help="path or slug fragment")
    status.set_defaults(func=cmd_status)

    listing = commands.add_parser("list", parents=[compat], help="list explanation trees")
    listing.set_defaults(func=cmd_list)

    opener = commands.add_parser(
        "open", parents=[compat], help="reopen a tree in the Kitty/Neovim workspace"
    )
    opener.add_argument("target", help="path or slug fragment")
    opener.set_defaults(func=cmd_open)

    doctor = commands.add_parser("doctor", parents=[compat], help="environment checks")
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
