#!/usr/bin/env python3
"""Build public installation notes without exposing build internals."""
from pathlib import Path
import sys

notes = Path(__file__).resolve().parents[1] / "docs/releases" / (sys.argv[1] + ".md")
print(notes.read_text() if notes.is_file() else "Improvements and fixes for Twister.\n")
print("""
## Install

Download **Twister-macOS-arm64.zip**, unzip it, and move **Twister.app** to Applications.
Requires Apple silicon and macOS 13 or later.

This community build is not signed with Apple Developer ID or notarized. macOS may
block its first launch. After attempting to open it, use **System Settings >
Privacy & Security > Open Anyway** if you trust this download.

Once installed, Twister checks for updates while running. Choose **Check for
Updates…** from its menu, or use **Settings > Updates**. You decide when to install;
active tasks finish before a restart. No GitHub account is needed.

Older source builds with updates disabled need this one-time manual installation.
Update feeds and downloads are signed and verified with Sparkle's Ed25519 keys.
""")
