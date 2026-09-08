import importlib.util
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import yaml


class ImportTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        os.environ["STATE_DIRECTORY"] = self.directory.name
        os.environ["MIHOMO"] = "mihomo"
        spec = importlib.util.spec_from_file_location(
            "importer", Path(__file__).with_name("mihomo-subscription.py")
        )
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.module.CACHE.write_bytes(b"previous subscription")

    def download(self, payload):
        return patch.object(self.module.HTTP, "open", return_value=io.BytesIO(payload))

    def test_invalid_download_preserves_cache(self):
        with self.download(b"Forbidden"), self.assertRaises(ValueError):
            self.module.import_subscription("https://provider.example/subscription")
        self.assertEqual(self.module.CACHE.read_bytes(), b"previous subscription")

    def test_refresh_failure_restores_previous_cache(self):
        payload = b"proxies: [{name: node, type: direct}]"
        with self.download(payload), patch.object(self.module.subprocess, "run") as run:
            run.return_value.returncode = 0
            with patch.object(self.module, "refresh", side_effect=[OSError(), None]) as refresh:
                with self.assertRaises(ValueError):
                    self.module.import_subscription("https://provider.example/subscription")
                self.assertEqual(refresh.call_count, 2)
        self.assertEqual(self.module.CACHE.read_bytes(), b"previous subscription")

    def test_import_discards_provider_system_settings(self):
        payload = b"proxies: [{name: node, type: direct}]\nmixed-port: 1234\nrules: [MATCH,DIRECT]"
        with self.download(payload), patch.object(self.module.subprocess, "run") as run:
            run.return_value.returncode = 0
            with patch.object(self.module, "refresh"):
                self.assertEqual(self.module.import_subscription("https://provider.example/subscription"), 1)
        self.assertEqual(yaml.safe_load(self.module.CACHE.read_text()), {"proxies": [{"name": "node", "type": "direct"}]})


if __name__ == "__main__":
    unittest.main()
