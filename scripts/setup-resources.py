#!/usr/bin/env python3
"""Acquire verified build resources and preserve their component notices."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request

ROOT = Path(__file__).resolve().parent.parent


def acquire(relative, url, digest):
    target = ROOT / relative
    if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() == digest:
        return
    with urllib.request.urlopen(url, timeout=90) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != digest:
        raise RuntimeError("Resource checksum mismatch: " + relative)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)


def main():
    acquire("Resources/PDFLib.js", "https://cdn.jsdelivr.net/npm/pdf-lib@1.17.1/dist/pdf-lib.min.js",
            "0f9a5cad07941f0826586c94e089d89b918c46e5c17cf2d5a3c6f666e3bc694f")
    acquire("Resources/licenses/pdf-lib.txt", "https://cdn.jsdelivr.net/npm/pdf-lib@1.17.1/LICENSE.md",
            "f2c9fc00fdb66eb99ac156ba52d734af66d8d309f65753ae809ad34ee2883bcb")
    bundle = ROOT / "Resources/PagesInterop.js"
    manifest = ROOT / "Resources/licenses/cupertino-files/provenance.json"
    valid = False
    if bundle.exists() and manifest.exists():
        metadata = json.loads(manifest.read_text())
        valid = (metadata["bundle"]["sha256"] == hashlib.sha256(bundle.read_bytes()).hexdigest()
                 and metadata["adapter"]["sha256"] == hashlib.sha256(
                     (ROOT / "scripts/pages-interop-entry.js").read_bytes()).hexdigest())
    if not valid:
        subprocess.run([sys.executable, str(ROOT / "scripts/setup-pages-interop.py")], check=True)
    tool = ROOT / "Tools/ExifTool"
    if tool.exists():
        for source, destination in [("README", "ExifTool-README.txt"), ("LICENSE", "ExifTool-LICENSE.txt")]:
            path = tool / source
            if path.exists():
                shutil.copyfile(path, ROOT / "Resources/licenses" / destination)
    print("Build resources verified.")


if __name__ == "__main__":
    main()
