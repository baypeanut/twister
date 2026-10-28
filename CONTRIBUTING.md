# Developing Twister

Twister targets Apple Silicon and macOS 13+. Use Xcode with Swift 6. There is no Windows app, web demo or hosted service in the supported product.

## Build and run

```sh
scripts/setup-exiftool.sh
python3 scripts/setup-resources.py
python3 scripts/setup-test-fixtures.py
swift build --product Twister
swift build --product twister-cli
scripts/build-app.sh debug
open build/Twister.app
```

`build-app.sh release` produces an optimized local package. Media and Office tools are downloaded on demand through setup. External executable overrides use `TWISTER_` followed by the uppercased tool name. Keep tool downloads, app packages, signing configuration and secrets out of version control.

## Source map

| Location | Purpose |
| --- | --- |
| `Sources/TwisterApp` | Native SwiftUI/AppKit interface, clipboard, Finder gestures, Library and window management |
| `Sources/TwisterCore` | Conversion engines, transactions, archives, document parsing, media and runtime setup |
| `Sources/TwisterUpdates` | Signed update transport and credential boundaries |
| `Sources/TwisterCLI` | `twister-cli` command-line entry point |
| `Tests` | Engine, security, update and regression tests |
| `Resources` | App metadata, localization, licenses, catalog and conversion interop resources |

Internal module names are stable implementation details; the package, executables, app identity and storage belong to Twister.

## Checks

```sh
swift test --parallel
python3 scripts/test-update-configuration.py
python3 scripts/test-release-audit.py
python3 scripts/generate-localizations.py --check
python3 scripts/test-native-ui.py
python3 scripts/audit-public-tree.py
python3 scripts/scan-secrets.py
```

Install FFmpeg, FFprobe, ExifTool and LibreOffice to exercise the complete conversion suite. Set `TWISTER_SOFFICE` when LibreOffice is outside the supported system paths. Live provider tests require their explicit environment opt-in. UI checks require a GUI login session and operate on the app's own generated fixtures. Do not automate a user's real windows or files for regression tests.

After changing `Sources/TwisterCore/Resources/Turkish.json`, regenerate native string tables with `python3 scripts/generate-localizations.py`.

## Change expectations

Preserve originals and existing destinations. Keep resource loading local and reject archive traversal. Use argument arrays for subprocesses, pinned hashes for runtime acquisition, and signature verification for updates. New fixes should include a focused regression when the behavior can recur unnoticed.

Default update configuration is intentionally disabled. Enabling it requires a Twister-owned repository or feed and a new signing key. Do not reuse another application's feed, keychain identity or signing trust.

Retain required third-party notices. Describe the user-facing change and the verification actually performed in pull requests.
