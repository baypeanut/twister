#!/usr/bin/env python3
"""Verify package scanning distinguishes local paths from ordinary prose."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ReleaseAuditTests(unittest.TestCase):
    def scan(self, content):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / "Twister.app"
            resources = app / "Contents/Resources"
            resources.mkdir(parents=True)
            for name in ["pdf-lib.txt", "ExifTool-LICENSE.txt", "Sparkle-LICENSE.txt", "cupertino-files/MIT.txt", "cupertino-files/BSD-3-Clause-lzfse.txt", "cupertino-files/PicoDocs-MIT.txt"]:
                notice = resources / "licenses" / name
                notice.parent.mkdir(parents=True, exist_ok=True)
                notice.write_text("fixture component notice")
            (resources / "component.txt").write_text(content)
            info = {"CFBundleIdentifier": "app.twister.desktop", "CFBundleExecutable": "Twister",
                    "TwisterExternalTools": True, "SUEnableAutomaticChecks": False}
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
            return subprocess.run([sys.executable, str(ROOT / "scripts/audit-release.py"), str(app), "--content-only"],
                                  env={**os.environ, "USER": "runner"}, capture_output=True, text=True)

    def test_common_username_words_are_not_personal_paths(self):
        self.assertEqual(self.scan("A task runner runs component checks.").returncode, 0)

    def test_actual_builder_home_paths_are_rejected_without_echoing_them(self):
        marker = "/Users/" + "runner" + "/private-project/"
        result = self.scan(marker)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(marker, result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which("codesign"), "requires macOS codesign")
    def test_a_package_without_hardened_runtime_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / "Twister.app"
            (app / "Contents/MacOS").mkdir(parents=True)
            for name in ["pdf-lib.txt", "ExifTool-LICENSE.txt", "Sparkle-LICENSE.txt", "cupertino-files/MIT.txt", "cupertino-files/BSD-3-Clause-lzfse.txt", "cupertino-files/PicoDocs-MIT.txt"]:
                notice = app / "Contents/Resources/licenses" / name
                notice.parent.mkdir(parents=True, exist_ok=True)
                notice.write_text("fixture component notice")
            info = {"CFBundleIdentifier": "app.twister.desktop", "CFBundleExecutable": "Twister",
                    "TwisterExternalTools": True, "SUEnableAutomaticChecks": False}
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
            shutil.copyfile("/usr/bin/true", app / "Contents/MacOS/Twister")
            subprocess.run(["codesign", "--force", "--sign", "-", "--options", "0", str(app)], check=True, capture_output=True)
            result = subprocess.run([sys.executable, str(ROOT / "scripts/audit-release.py"), str(app)],
                                    env={**os.environ, "USER": "runner"}, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing hardened runtime", result.stderr)

    def test_a_package_without_updates_must_not_embed_the_updater(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / "Twister.app"
            for name in ["pdf-lib.txt", "ExifTool-LICENSE.txt", "cupertino-files/MIT.txt", "cupertino-files/BSD-3-Clause-lzfse.txt", "cupertino-files/PicoDocs-MIT.txt"]:
                notice = app / "Contents/Resources/licenses" / name
                notice.parent.mkdir(parents=True, exist_ok=True)
                notice.write_text("fixture component notice")
            info = {"CFBundleIdentifier": "app.twister.desktop", "CFBundleExecutable": "Twister",
                    "TwisterExternalTools": True, "SUEnableAutomaticChecks": False}
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
            audit = lambda: subprocess.run([sys.executable, str(ROOT / "scripts/audit-release.py"), str(app), "--content-only"],
                                           env={**os.environ, "USER": "runner"}, capture_output=True, text=True)
            self.assertEqual(audit().returncode, 0, "no updater notice is needed without the updater")
            (app / "Contents/Frameworks/Sparkle.framework").mkdir(parents=True)
            self.assertNotEqual(audit().returncode, 0)

    @unittest.skipUnless(shutil.which("codesign"), "requires macOS codesign")
    def test_a_package_without_updates_keeps_library_validation(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / "Twister.app"
            (app / "Contents/MacOS").mkdir(parents=True)
            for name in ["pdf-lib.txt", "ExifTool-LICENSE.txt", "cupertino-files/MIT.txt", "cupertino-files/BSD-3-Clause-lzfse.txt", "cupertino-files/PicoDocs-MIT.txt"]:
                notice = app / "Contents/Resources/licenses" / name
                notice.parent.mkdir(parents=True, exist_ok=True)
                notice.write_text("fixture component notice")
            info = {"CFBundleIdentifier": "app.twister.desktop", "CFBundleExecutable": "Twister",
                    "TwisterExternalTools": True, "SUEnableAutomaticChecks": False}
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
            shutil.copyfile("/usr/bin/true", app / "Contents/MacOS/Twister")
            audit = lambda: subprocess.run([sys.executable, str(ROOT / "scripts/audit-release.py"), str(app)],
                                           env={**os.environ, "USER": "runner"}, capture_output=True, text=True)
            subprocess.run(["codesign", "--force", "--sign", "-", "--options", "runtime", str(app)], check=True, capture_output=True)
            self.assertEqual(audit().returncode, 0, audit().stderr)
            subprocess.run(["codesign", "--force", "--sign", "-", "--options", "runtime", "--entitlements", str(ROOT / "Configuration/LocalSigning.entitlements"), str(app)], check=True, capture_output=True)
            result = audit()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("library validation", result.stderr)

    def test_private_key_detection_remains_enforced(self):
        marker = "-----BEGIN " + "PRIVATE KEY-----"
        self.assertNotEqual(self.scan(marker).returncode, 0)


if __name__ == "__main__":
    unittest.main()
