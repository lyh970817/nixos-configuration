"""Pure logic for explainctl.

Everything here is testable without a Claude binary, a terminal, or Herdr:
metadata, root resolution, question-block parsing, the tree-wide flock,
snapshot/restore, launcher inference, and template rendering. cli.py owns
process execution and result emission.
"""

from __future__ import annotations

import dataclasses
import datetime
import fcntl
import hashlib
import json
import os
import re
import shutil
import tempfile
from pathlib import Path

METADATA_NAME = ".explain.json"
LOCK_NAME = ".explain.lock"
CONTEXT_NAME = ".context.md"
ROOT_DOCUMENT = "explanation.md"
CHILDREN_DIR = "children"
STAGING_DIR = ".staging"
SUBMIT_STAGING_PREFIX = ".submit-"
METADATA_VERSION = 1

# EX_TEMPFAIL: a concurrent update holds the tree lock; try again later.
EX_BUSY = 75

KNOWN_LAUNCHERS = ("claude", "claude-gpt56")

# Launcher name by CLAUDE_CONFIG_DIR basename. The gpt56 launcher owns its
# gateway/token environment, so only the launcher name is recorded — never
# credentials (see home/programs/claude.nix).
_CONFIG_DIR_LAUNCHERS = {
    "claude": "claude",
    "claude-gpt56": "claude-gpt56",
}


def iso_now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )


# ---------------------------------------------------------------------------
# Explanation store


def data_dir(environ=None) -> Path:
    environ = os.environ if environ is None else environ
    base = environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "explanations"


def slugify(question: str, max_length: int = 40) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", question.lower()).strip("-")
    if len(slug) > max_length:
        slug = slug[:max_length].rsplit("-", 1)[0] or slug[:max_length]
    return slug or "explanation"


def new_root(store: Path, question: str, now: datetime.datetime | None = None) -> Path:
    """Create and return a unique <timestamp>-<slug> directory in the store."""
    now = now or datetime.datetime.now()
    stem = f"{now:%Y%m%d-%H%M%S}-{slugify(question)}"
    store.mkdir(parents=True, exist_ok=True)
    candidate = store / stem
    suffix = 1
    while True:
        try:
            candidate.mkdir()
            return candidate
        except FileExistsError:
            suffix += 1
            candidate = store / f"{stem}-{suffix}"


def resolve_root(path: Path) -> Path | None:
    """Walk upward from a file or directory to the directory holding .explain.json."""
    current = Path(path).resolve()
    if current.is_file():
        current = current.parent
    while True:
        if (current / METADATA_NAME).is_file():
            return current
        if current.parent == current:
            return None
        current = current.parent


def tree_markdown_files(root: Path) -> list[Path]:
    """Every Markdown file in the tree, hidden entries (.staging, .submit-*)
    excluded. .context.md is handled separately by callers that need it."""
    files = []
    for path in sorted(root.rglob("*.md")):
        relative = path.relative_to(root)
        if any(part.startswith(".") for part in relative.parts):
            continue
        files.append(path)
    return files


# ---------------------------------------------------------------------------
# Metadata


def metadata_path(root: Path) -> Path:
    return Path(root) / METADATA_NAME


def new_metadata(slug: str, question: str, origin: dict) -> dict:
    now = iso_now()
    return {
        "version": METADATA_VERSION,
        "status": "creating",
        "slug": slug,
        "question": question,
        "created_at": now,
        "updated_at": now,
        "origin": origin,
        "coordinator_session_id": None,
        "root_document": ROOT_DOCUMENT,
        "last_sync_at": None,
    }


def write_metadata(root: Path, data: dict) -> None:
    path = metadata_path(root)
    fd, temporary = tempfile.mkstemp(prefix=".explain.json.", dir=str(root))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2, sort_keys=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def read_metadata(root: Path) -> dict:
    with open(metadata_path(root), encoding="utf-8") as handle:
        return json.load(handle)


def root_document(root: Path, metadata: dict) -> Path:
    relative = metadata.get("root_document") or ROOT_DOCUMENT
    return (Path(root) / relative).resolve()


# ---------------------------------------------------------------------------
# Origin resolution and launcher inference


def infer_launcher(config_dir: str | None) -> str | None:
    if not config_dir:
        return None
    return _CONFIG_DIR_LAUNCHERS.get(os.path.basename(os.path.normpath(config_dir)))


def resolve_origin(
    session_id: str | None,
    cwd: str | None,
    launcher: str | None,
    environ=None,
    process_cwd: str | None = None,
) -> dict:
    """Merge explicit --session-id/--cwd/--launcher flags with the
    CLAUDE_CODE_SESSION_ID fallback used when explainctl runs inside a
    Claude Code Bash tool. config_dir is recorded only when the launcher is
    unknown, so an unrecognized profile can still be resumed by exporting it.
    """
    environ = os.environ if environ is None else environ
    resolved_session = session_id or environ.get("CLAUDE_CODE_SESSION_ID") or None
    resolved_cwd = cwd or process_cwd or os.getcwd()
    resolved_launcher = launcher
    config_dir = None
    if resolved_launcher is None:
        env_config_dir = environ.get("CLAUDE_CONFIG_DIR") or str(
            Path.home() / ".config" / "claude"
        )
        resolved_launcher = infer_launcher(env_config_dir)
        if resolved_launcher is None:
            config_dir = env_config_dir
    return {
        "session_id": resolved_session,
        "cwd": str(Path(resolved_cwd).resolve()),
        "launcher": resolved_launcher,
        "config_dir": config_dir,
    }


# ---------------------------------------------------------------------------
# Question blocks

_BLOCK_RE = re.compile(
    r"<!--\s*explain-question\b(?P<attrs>[^>]*?)-->"
    r"(?P<body>.*?)"
    r"<!--\s*/explain-question\s*-->",
    re.DOTALL,
)
_ATTR_RE = re.compile(r'([A-Za-z_][\w-]*)\s*=\s*"([^"]*)"')


@dataclasses.dataclass
class Question:
    id: str
    status: str
    body: str
    file: Path | None = None
    line: int = 0

    @property
    def text(self) -> str:
        """The question with callout markers stripped, for prompts."""
        lines = []
        for line in self.body.strip().splitlines():
            stripped = line.strip()
            if stripped.startswith(">"):
                stripped = stripped[1:].strip()
            if stripped.startswith("[!"):
                continue
            lines.append(stripped)
        return "\n".join(line for line in lines if line).strip()


def parse_questions(text: str, file: Path | None = None) -> list[Question]:
    questions = []
    for match in _BLOCK_RE.finditer(text):
        attrs = dict(_ATTR_RE.findall(match.group("attrs")))
        identifier = attrs.get("id", "")
        if not identifier:
            continue
        questions.append(
            Question(
                id=identifier,
                status=attrs.get("status", ""),
                body=match.group("body"),
                file=file,
                line=text.count("\n", 0, match.start()) + 1,
            )
        )
    return questions


def open_questions(text: str, file: Path | None = None) -> list[Question]:
    return [q for q in parse_questions(text, file) if q.status == "open"]


def open_questions_in_tree(root: Path) -> list[Question]:
    questions = []
    for path in tree_markdown_files(root):
        questions.extend(open_questions(path.read_text(encoding="utf-8"), path))
    return questions


# ---------------------------------------------------------------------------
# Tree-wide lock

_LOCK_PLACEHOLDER = "explain-session tree lock; the kernel flock, not this file, is authoritative\n"


class ExplainBusy(Exception):
    def __init__(self, owner: dict | None):
        super().__init__("An explanation update is already running.")
        self.owner = owner or {}


class TreeLock:
    """Exclusive non-blocking flock on <root>/.explain.lock.

    The kernel lock is authoritative; the file content is only owner
    diagnostics for UIs. The file is never deleted, and the lock is released
    automatically if the holding process dies.
    """

    def __init__(self, root: Path):
        self.path = Path(root) / LOCK_NAME
        self.fd: int | None = None

    def acquire(self, operation: str, submitted: str | None = None) -> "TreeLock":
        fd = os.open(self.path, os.O_RDWR | os.O_CREAT, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            owner = self._read_owner(fd)
            os.close(fd)
            raise ExplainBusy(owner) from None
        self.fd = fd
        diagnostics = {
            "pid": os.getpid(),
            "started_at": iso_now(),
            "operation": operation,
            "submitted": submitted,
        }
        os.ftruncate(fd, 0)
        os.lseek(fd, 0, os.SEEK_SET)
        os.write(fd, (json.dumps(diagnostics, indent=2) + "\n").encode("utf-8"))
        return self

    def release(self) -> None:
        if self.fd is not None:
            # Closing drops the flock; the file itself stays for diagnostics.
            os.close(self.fd)
            self.fd = None

    def __enter__(self) -> "TreeLock":
        return self

    def __exit__(self, *_exc) -> None:
        self.release()

    @staticmethod
    def _read_owner(fd: int) -> dict:
        try:
            os.lseek(fd, 0, os.SEEK_SET)
            content = os.read(fd, 65536).decode("utf-8", "replace")
            owner = json.loads(content)
            return owner if isinstance(owner, dict) else {}
        except (OSError, ValueError):
            return {}

    @classmethod
    def probe(cls, root: Path) -> tuple[bool, dict]:
        """(locked, owner-diagnostics) without disturbing the diagnostics."""
        path = Path(root) / LOCK_NAME
        try:
            fd = os.open(path, os.O_RDWR)
        except FileNotFoundError:
            return False, {}
        try:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError:
                return True, cls._read_owner(fd)
            fcntl.flock(fd, fcntl.LOCK_UN)
            return False, cls._read_owner(fd)
        finally:
            os.close(fd)


# ---------------------------------------------------------------------------
# Submit staging

# The submit agent edits a private copy of the tree, never the live files:
# the laptop can rsync-push an edit at any moment, and the conflict check in
# cmd_submit compares live hashes taken before the agent ran against the live
# tree afterwards. Same filesystem as the root, so committing is os.replace.


def stage_tree(root: Path) -> Path:
    staging = Path(tempfile.mkdtemp(prefix=SUBMIT_STAGING_PREFIX, dir=str(root)))
    for path in _snapshot_targets(root):
        relative = path.relative_to(root)
        destination = staging / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
    return staging


def staged_targets(staging: Path) -> list[Path]:
    """Markdown files (plus .context.md) in a staging copy; mirrors
    _snapshot_targets but rooted at the staging directory."""
    files = []
    for path in sorted(Path(staging).rglob("*.md")):
        relative = path.relative_to(staging)
        if any(part.startswith(".") for part in relative.parts):
            continue
        files.append(path)
    context = Path(staging) / CONTEXT_NAME
    if context.is_file():
        files.append(context)
    return files


# ---------------------------------------------------------------------------
# Tree hashing


def _snapshot_targets(root: Path) -> list[Path]:
    targets = list(tree_markdown_files(root))
    context = root / CONTEXT_NAME
    if context.is_file():
        targets.append(context)
    return targets


def discard_staging(staging: Path) -> None:
    shutil.rmtree(staging, ignore_errors=True)


def hash_tree(root: Path) -> dict[str, str]:
    hashes = {}
    for path in _snapshot_targets(root):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        hashes[str(path.relative_to(root))] = digest
    return hashes


def diff_hashes(before: dict[str, str], after: dict[str, str]) -> tuple[list[str], list[str]]:
    """(updated, created) relative paths, each sorted."""
    updated = sorted(
        path for path, digest in after.items() if path in before and before[path] != digest
    )
    created = sorted(path for path in after if path not in before)
    return updated, created


# ---------------------------------------------------------------------------
# Prompt templates


def render_template(text: str, mapping: dict) -> str:
    """Simple {{name}} substitution; str.format would trip over LaTeX braces."""
    for key, value in mapping.items():
        text = text.replace("{{" + key + "}}", str(value))
    return text


def template_candidates(origin: dict, environ=None) -> list[Path]:
    environ = os.environ if environ is None else environ
    candidates = []
    override = environ.get("EXPLAINCTL_TEMPLATES")
    if override:
        candidates.append(Path(override))
    launcher = origin.get("launcher")
    config_home = Path(environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config"))
    if launcher in KNOWN_LAUNCHERS:
        candidates.append(config_home / launcher / "explain-session")
    if origin.get("config_dir"):
        candidates.append(Path(origin["config_dir"]) / "explain-session")
    candidates.append(config_home / "claude" / "explain-session")
    return candidates


def load_template(name: str, origin: dict, environ=None) -> str:
    tried = []
    for directory in template_candidates(origin, environ):
        path = directory / name
        tried.append(str(path))
        if path.is_file():
            return path.read_text(encoding="utf-8")
    raise FileNotFoundError(
        "explain-session template %r not found; tried: %s" % (name, ", ".join(tried))
    )
