#!/usr/bin/env python3
"""Fail a public macOS bundle on accidental credentials or builder identity."""
import os, re, shutil, subprocess, sys, plistlib
from pathlib import Path
arguments=[argument for argument in sys.argv[1:] if argument!='--content-only']
content_only=len(arguments)!=len(sys.argv)-1
root=Path(arguments[0]).resolve()
info=plistlib.loads((root/'Contents/Info.plist').read_bytes())
assert info.get('CFBundleIdentifier')=='app.twister.desktop'
assert info.get('CFBundleExecutable')=='Twister'
# A package without an update signing key cannot update, so it neither
# embeds the updater framework nor relaxes library validation for it.
updates=bool(info.get('SUPublicEDKey'))
sparkle_framework=root/'Contents/Frameworks/Sparkle.framework'
if updates:
    assert sparkle_framework.is_dir(), 'Configured updates require the updater framework'
else:
    assert not sparkle_framework.exists(), 'A package without updates must not embed the updater framework'
for notice in ['pdf-lib.txt', 'ExifTool-LICENSE.txt', 'cupertino-files/MIT.txt', 'cupertino-files/BSD-3-Clause-lzfse.txt', 'cupertino-files/PicoDocs-MIT.txt']+(['Sparkle-LICENSE.txt'] if updates else []):
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
# The app, Sparkle's helpers and every bundled executable use the hardened
# runtime. --content-only skips this for unsigned scanner fixtures.
signed=0
if not content_only:
    if not shutil.which('codesign'):sys.exit('Release audit failed: codesign is required to check signatures')
    sparkle=sparkle_framework/'Versions/B'
    code=[root]+([sparkle_framework,sparkle/'Autoupdate',sparkle/'Updater.app',sparkle/'XPCServices/Installer.xpc',sparkle/'XPCServices/Downloader.xpc'] if updates else [])
    code+=[root/'Contents/Resources/Tools'/name for name in ['ffmpeg','ffprobe','yt-dlp','deno'] if (root/'Contents/Resources/Tools'/name).exists()]
    missing=[]
    for item in code:
        result=subprocess.run(['codesign','--display','--verbose=1',str(item)],capture_output=True,text=True)
        flags=re.search(r'flags=(0x[0-9a-f]+)',result.stdout+result.stderr)
        if result.returncode!=0 or not flags or not int(flags.group(1),16)&0x10000:missing.append(str(item.relative_to(root.parent)))
    if missing:sys.exit('Release audit failed: missing hardened runtime: '+', '.join(missing))
    if not updates:
        result=subprocess.run(['codesign','--display','--entitlements','-','--xml',str(root)],capture_output=True)
        start=result.stdout.find(b'<?xml')
        entitlements=plistlib.loads(result.stdout[start:]) if start>=0 else {}
        if entitlements.get('com.apple.security.cs.disable-library-validation'):
            sys.exit('Release audit failed: a package without the updater framework must keep library validation')
    signed=len(code)
print(f'PASS public app boundary: {count} files; no local account, signing artifacts or token patterns'+(f'; hardened runtime on {signed} signed items' if signed else ''))
