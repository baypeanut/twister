#!/usr/bin/env python3
"""Exercise Sparkle's real ad-hoc install/relaunch and rejection paths in isolated apps."""
import functools
import http.server
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
SPARKLE = ROOT / '.build/artifacts/sparkle/Sparkle'
FRAMEWORK = SPARKLE / 'Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'


def run(*args):
    return subprocess.run(list(map(str, args)), check=True, capture_output=True, text=True, timeout=120).stdout.strip()


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def main():
    with tempfile.TemporaryDirectory(prefix='twister-update-install-') as directory:
        root = Path(directory)
        binary = root / 'UpdateSmoke'
        run('swiftc', '-swift-version', '6', ROOT / 'scripts/update-smoke.swift', '-o', binary,
            '-F', FRAMEWORK.parent, '-framework', 'Sparkle', '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks')
        key = root / 'signing.key'
        public_key = run('swift', '-e', '''import Foundation; import CryptoKit
let key = Curve25519.Signing.PrivateKey()
try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print(key.publicKey.rawRepresentation.base64EncodedString())''', key)
        key.chmod(0o600)
        for scenario in ('tampered-feed', 'tampered-archive', 'install'):
            case = root / scenario
            case.mkdir()
            handler = functools.partial(QuietHandler, directory=str(case))
            server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
            threading.Thread(target=server.serve_forever, daemon=True).start()
            url = f'http://127.0.0.1:{server.server_port}/'
            identifier = 'app.twister.update-smoke.' + uuid.uuid4().hex
            app = case / 'installed/UpdateSmoke.app'
            contents = app / 'Contents'
            (contents / 'MacOS').mkdir(parents=True)
            shutil.copy2(binary, contents / 'MacOS/UpdateSmoke')
            shutil.copytree(FRAMEWORK, contents / 'Frameworks/Sparkle.framework', symlinks=True)
            info = dict(CFBundleIdentifier=identifier, CFBundleName='UpdateSmoke', CFBundleExecutable='UpdateSmoke',
                        CFBundlePackageType='APPL', CFBundleVersion='1', CFBundleShortVersionString='1.0.0',
                        LSMinimumSystemVersion='13.0', LSUIElement=True, SmokeRoot=str(case),
                        SUFeedURL=url+'feed/appcast.xml', SUPublicEDKey=public_key,
                        SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True,
                        SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False, SUEnableSystemProfiling=False,
                        NSAppTransportSecurity={'NSAllowsLocalNetworking': True})
            (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
            framework = contents / 'Frameworks/Sparkle.framework'
            base = framework / 'Versions/B'
            for component in [base/'XPCServices/Installer.xpc', base/'XPCServices/Downloader.xpc',
                              base/'Autoupdate', base/'Updater.app', framework]:
                run('codesign', '--force', '--sign', '-', '--options', 'runtime', '--timestamp=none',
                    '--preserve-metadata=entitlements', component)
            def sign(bundle):
                run('codesign', '--force', '--sign', '-', '--options', 'runtime', '--timestamp=none',
                    '--entitlements', ROOT/'Configuration/LocalSigning.entitlements', bundle)
                run('codesign', '--verify', '--deep', '--strict', bundle)
            sign(app)
            candidate = case / 'candidate/UpdateSmoke.app'
            shutil.copytree(app, candidate, symlinks=True)
            updated = dict(info, CFBundleVersion='2', CFBundleShortVersionString='2.0.0')
            (candidate/'Contents/Info.plist').write_bytes(plistlib.dumps(updated))
            sign(candidate)
            feed = case / 'feed'
            feed.mkdir()
            archive = feed / 'UpdateSmoke.zip'
            run('python3', ROOT/'scripts/archive-app.py', candidate, archive)
            run(SPARKLE/'bin/generate_appcast', '--ed-key-file', key, '--maximum-deltas', '0',
                '--download-url-prefix', url+'feed/', feed)
            run(SPARKLE/'bin/sign_update', '--ed-key-file', key, '--verify', feed/'appcast.xml')
            if scenario == 'tampered-feed':
                content = (feed/'appcast.xml').read_text()
                (feed/'appcast.xml').write_text(content.replace('</title>', ' altered</title>', 1))
            elif scenario == 'tampered-archive':
                content = bytearray(archive.read_bytes())
                content[len(content)//2] ^= 1
                archive.write_bytes(content)
            result = case/'result.txt'
            process = None
            try:
                with (case/'process.log').open('w') as log:
                    process = subprocess.Popen([str(contents/'MacOS/UpdateSmoke')], stdout=log, stderr=log)
                    deadline = time.monotonic()+120
                    while not result.exists() and time.monotonic() < deadline:
                        time.sleep(0.25)
                    outcome = result.read_text() if result.exists() else 'timeout'
                    installed = plistlib.loads((contents/'Info.plist').read_bytes())['CFBundleVersion']
                    if scenario == 'install':
                        assert outcome == 'installed-and-relaunched' and installed == '2', outcome + '\n' + (case/'process.log').read_text()[-5000:]
                    else:
                        assert outcome.startswith('rejected:') and installed == '1', outcome
                        assert 'signature' in outcome.lower(), outcome
                    print(f'PASS {scenario}: ' + ('installed and relaunched version 2' if scenario == 'install' else 'signature rejected; original unchanged'), flush=True)
                    if process.poll() is None:
                        process.terminate()
                    process.wait(timeout=10)
            finally:
                if process is not None and process.poll() is None:
                    process.terminate()
                    process.wait(timeout=10)
                server.shutdown()
                subprocess.run(['defaults', 'delete', identifier], capture_output=True)


if __name__ == '__main__':
    main()
