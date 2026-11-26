#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("release_version", Path(__file__).with_name("release-version.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseVersionTests(unittest.TestCase):
    def test_stable_tag_and_monotonic_build(self):
        self.assertEqual(release.release_version("v0.3.0", []), ("0.3.0", "3000"))
        for older, newer in [("v0.3.999", "v0.4.0"), ("v0.999.999", "v1.0.0")]:
            self.assertLess(int(release.release_version(older, [])[1]), int(release.release_version(newer, [])[1]))

    def test_rejects_non_stable_tags(self):
        for tag in ["main", "v1.2", "v01.2.3", "v1.2.3-beta", "v1.2.3;echo nope", "v0.0.0", "v1.1000.0"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.release_version(tag, [])

    def test_existing_and_older_releases_are_immutable(self):
        for tag in ["v0.2.0", "v0.3.0"]:
            with self.assertRaises(ValueError):
                release.release_version(tag, [{"tag_name": "v0.3.0"}])
        with self.assertRaises(ValueError):
            release.release_version("v0.3.0", [{"tag_name": "v0.3.0", "draft": True}])

    def test_prerelease_does_not_block_stable(self):
        self.assertEqual(release.release_version("v0.3.0", [{"tag_name": "v0.4.0-beta", "prerelease": True}])[0], "0.3.0")


if __name__ == "__main__":
    unittest.main()
