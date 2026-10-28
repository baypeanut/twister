#!/usr/bin/env python3
"""Fetch hash-verified archive fixtures for local regression tests."""
import binascii
import hashlib
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = [{'file': 'test_read_format_rar.rar', 'source': 'https://raw.githubusercontent.com/libarchive/libarchive/master/libarchive/test/test_read_format_rar.rar.uu', 'sha256': 'd421b86f6290aefad61b2a36737253b2b30fe27c156bd95abfc230f24fe0307e', 'bytes': 336, 'purpose': 'Offline RAR4 and RAR5 interoperability test fixture'}, {'file': 'test_read_format_rar5_stored.rar', 'source': 'https://raw.githubusercontent.com/libarchive/libarchive/master/libarchive/test/test_read_format_rar5_stored.rar.uu', 'sha256': '35d75e315d164d2e329afc28f7d844f013271b4fcffd4ddd78efcdd114a383a7', 'bytes': 109, 'purpose': 'Offline RAR4 and RAR5 interoperability test fixture'}, {'file': 'test_read_format_rar5_compressed.rar', 'source': 'https://raw.githubusercontent.com/libarchive/libarchive/master/libarchive/test/test_read_format_rar5_compressed.rar.uu', 'sha256': '68f9d7e2662cd5bc5607ba9c6bf1edbf121cf3b08011a7d8643091791750a7c8', 'bytes': 436, 'purpose': 'Offline RAR4 and RAR5 interoperability test fixture'}]

def main():
    destination = ROOT / "Reference/archive-fixtures"
    destination.mkdir(parents=True, exist_ok=True)
    for item in FIXTURES:
        target = destination / item["file"]
        if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() == item["sha256"]:
            continue
        with urllib.request.urlopen(item["source"], timeout=60) as response:
            lines = response.read().splitlines()
        start = next(i for i, line in enumerate(lines) if line.startswith(b"begin "))
        data = bytearray()
        for line in lines[start + 1:]:
            if line == b"end": break
            data.extend(binascii.a2b_uu(line))
        if len(data) != item["bytes"] or hashlib.sha256(data).hexdigest() != item["sha256"]:
            raise RuntimeError("Fixture checksum mismatch: " + item["file"])
        target.write_bytes(data)
    photo = ROOT / "Tests/TwisterCoreTests/Fixtures/astronaut.png"
    digest = "88431cd9653ccd539741b555fb0a46b61558b301d4110412b5bc28b5e3ea6cb5"
    if not photo.exists() or hashlib.sha256(photo.read_bytes()).hexdigest() != digest:
        with urllib.request.urlopen("https://raw.githubusercontent.com/scikit-image/scikit-image/v0.25.2/skimage/data/astronaut.png", timeout=60) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != digest:
            raise RuntimeError("Photo fixture checksum mismatch")
        photo.parent.mkdir(parents=True, exist_ok=True)
        photo.write_bytes(data)
    print("Test fixtures verified.")

if __name__ == "__main__": main()
