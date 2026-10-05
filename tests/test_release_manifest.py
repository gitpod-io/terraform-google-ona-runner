import importlib.util
import io
import json
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "release_manifest", ROOT / ".github/scripts/release_manifest.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ReleaseManifestTest(unittest.TestCase):
    def setUp(self):
        self.version = "20261002.737"
        self.manifest = {
            "version": self.version,
            "runner_image": f"registry.example/runner:{self.version}",
            "proxy_image": f"registry.example/proxy:{self.version}",
            "prometheus_image": "registry.example/prometheus:v3.13.2",
            "node_exporter_image": "registry.example/node-exporter:v1.12.1",
            "cli_url": "https://example.com/cli",
            "supervisor_url": "https://example.com/supervisor",
            "vm_image": "projects/example/global/images/environment",
        }
        self.locals_text = "\n".join(
            f'  default_{field} = "{self.manifest[field]}"'
            for field in MODULE.IMAGE_FIELDS
        )

    def fetch(self, manifest):
        response = io.BytesIO(json.dumps(manifest).encode())
        return patch.object(MODULE.urllib.request, "urlopen", return_value=response)

    def test_fetches_pinned_version_and_preserves_assets(self):
        with self.fetch(self.manifest) as fetch:
            self.assertEqual(MODULE.release_manifest(self.locals_text), self.manifest)
        fetch.assert_called_once_with(
            f"https://storage.googleapis.com/gitpod-runner-releases/gcp/releases/{self.version}/manifest.json",
            timeout=30,
        )

    def test_rejects_mismatched_version_or_images(self):
        for field in ("version", *MODULE.IMAGE_FIELDS):
            with self.subTest(field=field), self.fetch({**self.manifest, field: "old"}):
                with self.assertRaisesRegex(ValueError, field):
                    MODULE.release_manifest(self.locals_text)

    def test_rejects_missing_assets(self):
        for field in ("cli_url", "supervisor_url", "vm_image"):
            with self.subTest(field=field), self.fetch({**self.manifest, field: None}):
                with self.assertRaisesRegex(ValueError, field):
                    MODULE.release_manifest(self.locals_text)

    def test_rejects_missing_or_duplicate_defaults_before_fetching(self):
        for text in ("", self.locals_text + "\n" + self.locals_text):
            with self.subTest(text=text), self.fetch(self.manifest) as fetch:
                with self.assertRaisesRegex(ValueError, "Expected one literal"):
                    MODULE.release_manifest(text)
                fetch.assert_not_called()

    def test_rejects_unversioned_runner_before_fetching(self):
        with self.fetch(self.manifest) as fetch:
            with self.assertRaisesRegex(ValueError, "release tag"):
                MODULE.release_manifest(self.locals_text.replace(self.version, "latest"))
            fetch.assert_not_called()

    def test_does_not_fall_back_when_pinned_manifest_is_unavailable(self):
        error = urllib.error.HTTPError("https://example.com", 404, "Not Found", {}, None)
        with patch.object(MODULE.urllib.request, "urlopen", side_effect=error) as fetch:
            with self.assertRaises(urllib.error.HTTPError):
                MODULE.release_manifest(self.locals_text)
            self.assertEqual(fetch.call_count, 1)


if __name__ == "__main__":
    unittest.main()
