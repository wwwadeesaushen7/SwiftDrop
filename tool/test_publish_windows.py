import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from publish_windows import publish


class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "pubspec.yaml").write_text("name: swiftdrop\nversion: 0.3.0+3\n")
        self.artifact = self.root / "artifact"
        self.artifact.mkdir()
        self.commit = "a" * 40
        self.name = "SwiftDrop-0.3.0-windows-x64-setup.exe"
        # Publisher tests check the artifact contract, not Windows execution.
        data = b"installer fixture bytes"
        (self.artifact / self.name).write_bytes(data)
        self.info = {
            "version": "0.3.0", "build_number": 3, "source_commit": self.commit,
            "application_version": "0.3.0.3", "installer_version": "0.3.0",
            "installer_filename": self.name, "installer_sha256": hashlib.sha256(data).hexdigest(),
            "installer_bytes": len(data),
        }

    def run_publish(self, result="success"):
        (self.artifact / "BUILD-INFO.json").write_text(json.dumps(self.info))
        return publish(self.root, self.artifact, self.commit, result, "https://github.com/me/app/actions/runs/1", "me/app")

    def test_publishes_exact_checked_file_and_matching_checksum(self):
        status = self.run_publish()
        self.assertEqual(status["version"], "0.3.0")
        self.assertEqual((self.root / "downloads" / self.name).read_bytes(), b"installer fixture bytes")
        self.assertIn(self.name, (self.root / "downloads/WINDOWS.md").read_text())
        self.assertIn(self.info["installer_sha256"], (self.root / "downloads/SwiftDrop-0.3.0-windows-x64-SHA256SUMS.txt").read_text())

    def test_rejects_old_app_installer_source_or_build_metadata(self):
        for field, value in [("version", "0.2.0"), ("installer_version", "0.2.0"),
                             ("application_version", "0.2.0.2"), ("build_number", 2),
                             ("source_commit", "b" * 40), ("installer_filename", "../old.exe")]:
            with self.subTest(field=field):
                old = self.info[field]
                self.info[field] = value
                with self.assertRaises(ValueError): self.run_publish()
                self.info[field] = old
                self.assertFalse((self.root / "downloads" / self.name).exists())

    def test_corruption_preserves_previous_download(self):
        self.run_publish()
        (self.artifact / self.name).write_bytes(b"corrupted file")
        with self.assertRaises(ValueError): self.run_publish()
        self.assertEqual((self.root / "downloads" / self.name).read_bytes(), b"installer fixture bytes")

    def test_failure_reports_status_without_substituting_old_installer(self):
        status = self.run_publish("failure")
        self.assertEqual(status["status"], "failure")
        self.assertFalse((self.root / "downloads" / self.name).exists())
        self.assertIn("did not produce a verified installer", (self.root / "downloads/WINDOWS.md").read_text())


if __name__ == "__main__":
    unittest.main()
