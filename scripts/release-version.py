#!/usr/bin/env python3
"""Validate a stable release tag and derive a monotonic Sparkle build number."""
import json
import re
import sys
from pathlib import Path


def parse_tag(tag):
    match = re.fullmatch(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", tag)
    if not match:
        raise ValueError("Use a stable version tag such as v0.3.0, without suffixes or leading zeros")
    parts = tuple(map(int, match.groups()))
    if any(part > 999 for part in parts) or parts == (0, 0, 0):
        raise ValueError("Version components must be 0..999 and the version must be greater than zero")
    return parts


def release_version(tag, releases):
    parts = parse_tag(tag)
    for release in releases:
        if release["tag_name"] == tag:
            raise ValueError("This tag already has a release; published artifacts must remain immutable")
        if release.get("draft") or release.get("prerelease"):
            continue
        try:
            previous = parse_tag(release["tag_name"])
        except ValueError:
            raise ValueError("An existing stable release has an unrecognized tag; review it before publishing")
        if previous >= parts:
            raise ValueError("The version must be newer than every published stable release")
    return tag[1:], str(parts[0] * 1_000_000 + parts[1] * 1_000 + parts[2])


if __name__ == "__main__":
    try:
        pages = json.loads(Path(sys.argv[2]).read_text())
        releases = [release for page in pages for release in page] if pages and isinstance(pages[0], list) else pages
        version, build = release_version(sys.argv[1], releases)
        print(f"version={version}\nbuild={build}")
    except (ValueError, KeyError, OSError) as error:
        sys.exit(str(error))
