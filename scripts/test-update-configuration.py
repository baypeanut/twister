#!/usr/bin/env python3
"""Regression tests for Twister's build-time update trust boundary."""
import base64
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("configure_updates", ROOT / "scripts/configure-updates.py")
configure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(configure)


class UpdateConfigurationTests(unittest.TestCase):
    def apply(self, configuration, inherited=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bundle = root / "Info.plist"
            source = root / "Updates.plist"
            bundle.write_bytes(plistlib.dumps(inherited or {}))
            if configuration is not None:
                source.write_bytes(plistlib.dumps(configuration))
            configure.apply_configuration(bundle, source, environ={})
            return plistlib.loads(bundle.read_bytes())

    def test_default_configs_disable_all_inherited_upstream_trust(self):
        for path in ("Configuration/Updates.plist", "Configuration/Updates.public.plist"):
            configuration = plistlib.loads((ROOT / path).read_bytes())
            self.assertIs(configuration.get("Enabled"), False)
            inherited = {"SUPublicEDKey": "upstream-key", "SUFeedURL": "https://example.com/upstream",
                         "TwisterPublicUpdateRepository": "upstream/app", "SUEnableAutomaticChecks": True,
                         "TwisterPublicUpdateRepository": "stale/repository"}
            result = self.apply(configuration, inherited)
            for key in ("SUPublicEDKey", "SUFeedURL", "TwisterPublicUpdateRepository", "TwisterPublicUpdateRepository"):
                self.assertNotIn(key, result)
            self.assertIs(result["SUEnableAutomaticChecks"], False)
            self.assertIs(result["TwisterExternalTools"], True)

    def test_missing_config_cannot_preserve_an_inherited_signing_key(self):
        result = self.apply(None, {"SUPublicEDKey": base64.b64encode(b"x" * 32).decode(),
                                  "SUFeedURL": "https://example.com/stale"})
        self.assertNotIn("SUPublicEDKey", result)
        self.assertNotIn("SUFeedURL", result)
        self.assertIs(result["SUEnableAutomaticChecks"], False)

    def test_independent_public_channel_requires_exact_feed_and_valid_key(self):
        key = base64.b64encode(b"t" * 32).decode()
        configuration = {"PublicEDKey": key, "PublicRepository": "baypeanut/twister",
                         "FeedURL": "https://github.com/baypeanut/twister/releases/latest/download/appcast.xml"}
        result = self.apply(configuration)
        self.assertEqual(result["TwisterPublicUpdateRepository"], "baypeanut/twister")
        self.assertEqual(result["SUPublicEDKey"], key)
        for changes in ({"PublicEDKey": "invalid"}, {"FeedURL": "http://example.com/feed"},
                        {"PublicRepository": "different/repository"},
                        {"FeedURL": "https://user:password@example.com/feed"}):
            with self.assertRaises(ValueError):
                self.apply(configuration | changes)

    def test_local_development_exception_never_allows_remote_http(self):
        key = base64.b64encode(b"t" * 32).decode()
        result = self.apply({"PublicEDKey": key, "LocalDevelopment": True,
                             "FeedURL": "http://127.0.0.1:8765/feed"})
        self.assertIs(result["TwisterLocalUpdateFeed"], True)
        with self.assertRaises(ValueError):
            self.apply({"PublicEDKey": key, "LocalDevelopment": True,
                        "FeedURL": "http://192.168.0.1/feed"})


if __name__ == "__main__":
    unittest.main()
