#!/usr/bin/env python3
"""Fail a public macOS bundle on accidental credentials or builder identity."""
import os, re, sys, plistlib
from pathlib import Path
root=Path(sys.argv[1]).resolve()
info=plistlib.loads((root/'Contents/Info.plist').read_bytes())
assert info.get('CFBundleIdentifier')=='app.twister.desktop'
assert info.get('CFBundleExecutable')=='Twister'
for notice in ['pdf-lib.txt', 'ExifTool-LICENSE.txt', 'Sparkle-LICENSE.txt', 'cupertino-files/MIT.txt', 'cupertino-files/BSD-3-Clause-lzfse.txt', 'cupertino-files/PicoDocs-MIT.txt']:
    assert (root/'Contents/Resources/licenses'/notice).is_file(), 'Missing component notice: '+notice
if info.get('SUFeedURL'):
    assert info.get('TwisterPublicUpdateRepository')=='baypeanut/twister'
    assert info.get('SUFeedURL')=='https://github.com/baypeanut/twister/releases/latest/download/appcast.xml'
    assert info.get('SUPublicEDKey'), 'Configured updates require independent signing trust'
else:
    assert not info.get('SUPublicEDKey'), 'Unconfigured packages must not inherit another signing key'
    assert not info.get('SUEnableAutomaticChecks'), 'Unconfigured packages must not check for updates'
assert info.get('TwisterExternalTools') is True
assert not (root/'Contents/XPCServices').exists(), 'Public archive must not include a private credential broker'
assert not (root/'Contents/Resources/Tools/ffmpeg').exists(), 'Upstream media tools use direct first-use acquisition'
assert not (root/'Contents/Resources/Tools/LibreOffice.app').exists()
username=os.environ.get('USER','').encode()
# A bare login such as "runner" is ordinary prose and a common symbol name.
# Match actual builder home paths rather than unrelated component vocabulary.
identity_paths=[str(Path.home()).encode()+b'/']
if username:
    identity_paths.extend([b'/Users/'+username+b'/',b'/home/'+username+b'/'])
issues=[];count=0
for path in root.rglob('*'):
    if not path.is_file() or path.is_symlink(): continue
    count+=1;data=path.read_bytes()
    if path.name.startswith('.env') or path.suffix.lower() in {'.p12','.pfx','.key','.mobileprovision'}:issues.append(str(path.relative_to(root)))
    patterns=[rb'-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----',rb'github_pat_[A-Za-z0-9_]{20,}',rb'gh[pousr]_[A-Za-z0-9]{20,}']
    if any(re.search(pattern,data) for pattern in patterns) or any(marker in data for marker in identity_paths):issues.append(str(path.relative_to(root)))
if issues:sys.exit('Release audit failed: '+', '.join(sorted(set(issues))))
print(f'PASS public app boundary: {count} files; no local account, signing artifacts or token patterns')
