"""Two structural properties that are easier to break than to notice.

1. `scansci_pdf` must never be imported into this process. Importing it sets
   `os.environ["NO_PROXY"] = "*"` process-wide and monkey-patches
   `ssl.SSLContext.load_default_certs`, either of which would quietly change
   how this process reaches KCL's IdP and the publishers. The separation is a
   subprocess boundary or nothing.
2. There is no batch entry point. A future `get --all` would defeat every limit
   in `gate`, because the gate can only refuse what it is asked about.
"""

from __future__ import annotations

import ast
import contextlib
import io
import unittest
from pathlib import Path

import kcl_fetch

ROOT = Path(__file__).resolve().parent.parent


@contextlib.contextmanager
def quiet():
    """argparse writes its usage banner to stderr before exiting."""
    with contextlib.redirect_stderr(io.StringIO()):
        yield


def python_sources():
    yield ROOT / "kcl_fetch.py"
    yield from sorted((ROOT / "kcl_fetch_lib").glob("*.py"))


def imported_modules(path: Path) -> set[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"))
    names: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
            names.add(node.module.split(".")[0])
    return names


class TestNoScansciImport(unittest.TestCase):
    def test_no_source_file_imports_scansci_pdf(self):
        for path in python_sources():
            with self.subTest(path=path.name):
                self.assertNotIn("scansci_pdf", imported_modules(path))

    def test_scansci_pdf_is_not_in_sys_modules_after_importing_everything(self):
        import sys

        import kcl_fetch_lib  # noqa: F401
        from kcl_fetch_lib import driver, gate, libkey, metadata, routing, urls  # noqa: F401

        self.assertNotIn("scansci_pdf", sys.modules)

    def test_importing_this_package_leaves_the_proxy_environment_alone(self):
        import os

        from kcl_fetch_lib import driver, gate, libkey, metadata, routing, urls  # noqa: F401

        self.assertNotEqual(os.environ.get("NO_PROXY"), "*")

    def test_importing_this_package_leaves_ssl_unpatched(self):
        import ssl

        self.assertEqual(
            ssl.SSLContext.load_default_certs.__qualname__,
            "SSLContext.load_default_certs",
        )


class TestCliSurface(unittest.TestCase):
    def parser(self):
        return kcl_fetch.build_parser()

    def test_the_only_subcommands_are_get_login_and_status(self):
        actions = [
            action
            for action in self.parser()._subparsers._group_actions
            if hasattr(action, "choices")
        ]
        self.assertEqual(set(actions[0].choices), {"get", "login", "status"})

    def test_get_accepts_exactly_one_doi(self):
        args = self.parser().parse_args(["get", "10.1000/abc", "-o", "/tmp"])
        self.assertEqual(args.doi, "10.1000/abc")
        with quiet(), self.assertRaises(SystemExit):
            self.parser().parse_args(["get", "10.1000/abc", "10.1000/def"])

    def test_there_is_no_batch_subcommand_to_invoke(self):
        for name in ("batch", "bulk", "get-all", "issue", "fetch-many"):
            with self.subTest(name=name):
                with quiet(), self.assertRaises(SystemExit):
                    self.parser().parse_args([name, "x"])


if __name__ == "__main__":
    unittest.main()
