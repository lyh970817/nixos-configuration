"""Deterministic LaTeX -> Typst math conversion for explanation trees.

Agents keep writing LaTeX math (the templates are deliberately minimal);
this module is the deterministic layer that converts their output to the
tree's canonical Typst syntax. Markdown structure is untouched: only the
contents of `$...$` and `$$...$$` segments are rewritten, code fences and
inline code are protected, and `$$...$$` stays the display marker (Typst
inline math carries no inner padding, matching the pilot conversion).

The t2l CLI (pkgs/tylax, `t2l --direction l2t`) does the syntax conversion;
three hazards it leaves behind are post-processed here, matching what the
pilot conversion of the real corpus needed:

- literal `%` inside math (a comment in LaTeX, a render hazard in the
  Obsidian/Typst pipeline) becomes `#sym.percent`;
- nested `$` inside math (`\\text{... $x$ ...}` -> `#text[... $x$ ...]`)
  is un-nested into quoted text and bare math (`"... " x " ..."`);
- t2l's spaced digit literals (`0 . 1 5` for `0.15`) are collapsed.

All post-processing is idempotent, but t2l itself is not: running it over
Typst math mangles it. Callers therefore only convert content an agent just
produced (diffed regions), or whole trees exactly once (the migration
marker in .explain.json).
"""

from __future__ import annotations

import difflib
import os
import re
import shutil
import subprocess

MATH_SYNTAX_KEY = "math_syntax"
MATH_SYNTAX_TYPST = "typst"
MATH_SYNTAX_LATEX = "latex"

T2L_ENV = "EXPLAINCTL_T2L"


class ConversionWarning:
    """One math segment t2l could not convert; the original is kept."""

    def __init__(self, segment: str, detail: str):
        self.segment = segment
        self.detail = detail

    def as_dict(self) -> dict:
        return {"segment": self.segment[:200], "detail": self.detail}


def t2l_binary(environ=None) -> str:
    environ = os.environ if environ is None else environ
    return environ.get(T2L_ENV) or "t2l"


def t2l_available(environ=None) -> bool:
    return shutil.which(t2l_binary(environ)) is not None


def run_t2l(source: str, environ=None) -> str:
    """LaTeX -> Typst through the t2l CLI; raises on a failed invocation."""
    completed = subprocess.run(
        [t2l_binary(environ), "--direction", "l2t", "--no-preamble", "-q"],
        input=source,
        capture_output=True,
        text=True,
        check=True,
    )
    return completed.stdout.strip()


# ---------------------------------------------------------------------------
# Post-processing


def collapse_digits(text: str) -> str:
    """t2l explodes number literals into spaced digits ('0 . 1 5' for
    '0.15'); join them back so Typst renders number literals."""
    previous = None
    while previous != text:
        previous = text
        text = re.sub(r"(\d) (\d)", r"\1\2", text)
        text = re.sub(r"(\d) ?\. ?(\d)", r"\1.\2", text)
    return text


# Regions whose content is literal text, not math: quoted strings and
# `#text[...]` bodies. `%` and spaced digits inside them are the author's
# literal text and must not be rewritten.
_TEXT_REGION_RE = re.compile(r'"(?:[^"\\]|\\.)*"|#text\[[^\[\]]*\]')


def _outside_text_regions(content: str, transform) -> str:
    parts = []
    last = 0
    for match in _TEXT_REGION_RE.finditer(content):
        parts.append(transform(content[last : match.start()]))
        parts.append(match.group(0))
        last = match.end()
    parts.append(transform(content[last:]))
    return "".join(parts)


def replace_percent(content: str) -> str:
    return _outside_text_regions(content, lambda part: part.replace("%", "#sym.percent"))


def _quote_text(text: str) -> str:
    return '"%s"' % text.replace("\\", "\\\\").replace('"', '\\"')


_NESTED_TEXT_RE = re.compile(r"#text\[([^\[\]]*)\]")


def unnest_text_math(content: str, convert_inner) -> str:
    """`#text[...]` bodies still carry the LaTeX verbatim, so nested math
    (`#text[rate is $x$ high]`) must be split into quoted text and bare math
    (`"rate is " x " high"`), the inner LaTeX converted on the way."""

    def fix(match: re.Match) -> str:
        body = match.group(1)
        if "$" not in body:
            return match.group(0)
        pieces = []
        for index, part in enumerate(re.split(r"\$(.*?)\$", body)):
            if index % 2:
                converted = convert_inner(part.strip())
                if converted:
                    pieces.append(converted)
            elif part:
                pieces.append(_quote_text(part))
        return " ".join(pieces)

    return _NESTED_TEXT_RE.sub(fix, content)


# ---------------------------------------------------------------------------
# Segment conversion


class _Converter:
    """One conversion pass: t2l invocation plus post-processing, warnings
    collected instead of raised so a stubborn segment never loses content."""

    def __init__(self, run=None):
        self.run = run or run_t2l
        self.warnings: list[ConversionWarning] = []

    def _postprocess(self, content: str) -> str:
        content = unnest_text_math(content, self._inner_inline)
        content = replace_percent(content)
        content = _outside_text_regions(content, collapse_digits)
        return content

    def _inner_inline(self, latex: str) -> str:
        """Nested math inside \\text{...}: convert, fall back to the raw
        LaTeX body (minus the `$`s that must not nest) on failure."""
        if not latex:
            return ""
        try:
            out = self.run("$%s$" % latex)
        except (OSError, subprocess.SubprocessError):
            return latex
        match = re.fullmatch(r"\$(.*)\$", out, re.DOTALL)
        if not match:
            return latex
        return self._postprocess(match.group(1).strip())

    def convert_segment(self, latex: str, display: bool) -> str | None:
        source = "$$%s$$" % latex if display else "$%s$" % latex
        try:
            out = self.run(source)
        except (OSError, subprocess.SubprocessError) as error:
            self.warnings.append(ConversionWarning(latex, str(error)))
            return None
        # Typst display math is `$ content $`; inline is unpadded `$content$`.
        match = re.fullmatch(r"\$\s?(.*?)\s?\$", out, re.DOTALL)
        if not match:
            self.warnings.append(
                ConversionWarning(latex, "unexpected t2l output: %r" % out[:200])
            )
            return None
        return self._postprocess(match.group(1))


# ---------------------------------------------------------------------------
# Markdown segmentation

_FENCE_RE = re.compile(r"^(?:```|~~~).*?^(?:```|~~~)[ \t]*$", re.DOTALL | re.MULTILINE)
_INLINE_CODE_RE = re.compile(r"`[^`\n]+`")
_DISPLAY_RE = re.compile(r"\$\$(.+?)\$\$", re.DOTALL)


def _overlaps(span: tuple[int, int], spans) -> bool:
    return any(span[0] < end and start < span[1] for start, end in spans)


def _protected_spans(text: str) -> list[tuple[int, int]]:
    spans = [match.span() for match in _FENCE_RE.finditer(text)]
    for match in _INLINE_CODE_RE.finditer(text):
        if not _overlaps(match.span(), spans):
            spans.append(match.span())
    return spans


def _inline_spans(text: str) -> list[tuple[int, int]]:
    """Inline `$...$` spans, delimiters included. A scanner, not a regex:
    LaTeX like `$\\text{rate is $x$ high}$` legitimately nests `$` inside
    braces, so a `$` only closes the segment at brace depth zero. Inline
    math never crosses a line break; escaped `\\$` is never a delimiter."""
    spans = []
    i = 0
    length = len(text)
    while i < length:
        char = text[i]
        if char == "\\":
            i += 2
            continue
        if char != "$":
            i += 1
            continue
        if i + 1 < length and text[i + 1] == "$":
            i += 2
            continue
        depth = 0
        j = i + 1
        while j < length:
            inner_char = text[j]
            if inner_char == "\\":
                j += 2
                continue
            if inner_char == "\n":
                break
            if inner_char == "{":
                depth += 1
            elif inner_char == "}":
                depth = max(0, depth - 1)
            elif inner_char == "$" and depth == 0:
                break
            j += 1
        if j < length and text[j] == "$" and j > i + 1:
            spans.append((i, j + 1))
            i = j + 1
        else:
            i += 1
    return spans


def _math_segments(text: str) -> list[tuple[int, int, str, bool]]:
    """(start, end, inner, display) for every math segment outside code."""
    protected = _protected_spans(text)
    segments = []
    taken: list[tuple[int, int]] = []
    for match in _DISPLAY_RE.finditer(text):
        if _overlaps(match.span(), protected):
            continue
        segments.append((match.start(), match.end(), match.group(1), True))
        taken.append(match.span())
    for start, end in _inline_spans(text):
        if _overlaps((start, end), protected) or _overlaps((start, end), taken):
            continue
        segments.append((start, end, text[start + 1 : end - 1], False))
    segments.sort()
    return segments


def changed_spans(before: str, after: str) -> list[tuple[int, int]]:
    """Character spans in `after` covered by lines added or changed relative
    to `before` — the regions an agent just produced."""
    before_lines = before.splitlines(keepends=True)
    after_lines = after.splitlines(keepends=True)
    offsets = [0]
    for line in after_lines:
        offsets.append(offsets[-1] + len(line))
    matcher = difflib.SequenceMatcher(a=before_lines, b=after_lines, autojunk=False)
    spans = []
    for tag, _i1, _i2, j1, j2 in matcher.get_opcodes():
        if tag in ("replace", "insert") and j2 > j1:
            spans.append((offsets[j1], offsets[j2]))
    return spans


def convert_markdown(text: str, run=None, only_spans=None) -> tuple[str, list[ConversionWarning]]:
    """Convert LaTeX math segments in Markdown to Typst.

    `only_spans` restricts conversion to segments overlapping the given
    character spans (see changed_spans); None converts every segment. A
    segment kept verbatim after a converter failure is reported as a warning,
    never dropped.
    """
    converter = _Converter(run)
    out = text
    for start, end, inner, display in reversed(_math_segments(text)):
        if only_spans is not None and not _overlaps((start, end), only_spans):
            continue
        converted = converter.convert_segment(inner, display)
        if converted is None:
            continue
        wrapped = "$$%s$$" % converted if display else "$%s$" % converted
        out = out[:start] + wrapped + out[end:]
    return out, converter.warnings


def convert_changed(before: str | None, after: str, run=None):
    """Convert only the math the agent just wrote: everything for a new file,
    the diffed regions for an edited one (pre-existing math is already Typst
    and must never pass through t2l again)."""
    if before is None:
        return convert_markdown(after, run)
    spans = changed_spans(before, after)
    if not spans:
        return after, []
    return convert_markdown(after, run, only_spans=spans)
