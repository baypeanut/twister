#!/usr/bin/env python3
"""Prove that building the CLI cannot replace the macOS application binary."""
import hashlib
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent

def run(*args):
    return subprocess.run(args, cwd=root, check=True, capture_output=True, text=True).stdout

package = json.loads(run('swift', 'package', 'dump-package'))
names = [product['name'].casefold() for product in package['products']]
assert len(names) == len(set(names)), 'Product names collide on the default macOS filesystem'
run('swift', 'build', '--product', 'Twister')
binaries = Path(run('swift', 'build', '--show-bin-path').strip())
app = binaries / 'Twister'
before = hashlib.sha256(app.read_bytes()).digest()
run('swift', 'build', '--product', 'twister-cli')
assert hashlib.sha256(app.read_bytes()).digest() == before, 'Building the CLI replaced the application'
cli = binaries / 'twister-cli'
assert not cli.samefile(app), 'The app and CLI resolve to the same filesystem object'
for executable in [app, cli]:
    catalog = json.loads(run(str(executable), 'catalog'))
    assert catalog['conversionMatrix'] and catalog['tools']
print('PASS: case-insensitive product identity, independent binaries and both catalogs')
