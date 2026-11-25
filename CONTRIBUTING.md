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

`build-app.sh release` produces an optimized local package; `TWISTER_WEB_DOWNLOADS=0` in its environment leaves the web downloader out. A package whose update configuration carries no update signing key neither links nor embeds the updater framework and keeps library validation on; only update-enabled ad-hoc or locally signed packages relax it for that framework. Media, Office and the optional Web download tools are downloaded on demand through setup, each group by itself. External executable overrides use `TWISTER_` followed by the uppercased tool name; debug builds and `twister-cli` honor them, packaged apps ignore them. Keep tool downloads, app packages, signing configuration and secrets out of version control.

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

Install FFmpeg, FFprobe, ExifTool and LibreOffice to exercise the complete conversion suite.

Packages with bundled tools (an update configuration with `ExternalTools` set to false) copy `Tools/LibreOffice.app` only when it is LibreOffice 26.8.3 (`twister_libreoffice_version` in `scripts/tool-pins.sh`) with The Document Foundation's signature. To refresh it, download the 26.8.3 disk image for Apple Silicon from The Document Foundation, check it against the published SHA-256 (the same value as `officePackage` in `ExternalToolSetup.swift`), copy `LibreOffice.app` out of it to a folder of your choice, remove `Tools/LibreOffice.app`, and run `TWISTER_LIBREOFFICE_SOURCE=/path/to/LibreOffice.app scripts/setup-tools.sh`. `TWISTER_BUNDLED_OFFICE=0 scripts/build-app.sh` leaves LibreOffice out of such a package to check the other tools in the meantime. Set `TWISTER_SOFFICE` when LibreOffice is outside the supported system paths. Live provider tests require their explicit environment opt-in. UI checks require a GUI login session and operate on the app's own generated fixtures. Do not automate a user's real windows or files for regression tests.

After changing `Sources/TwisterCore/Resources/Turkish.json`, regenerate native string tables with `python3 scripts/generate-localizations.py`.

## Change expectations

Preserve originals and existing destinations. Keep resource loading local and reject archive traversal. Use argument arrays for subprocesses, pinned hashes for runtime acquisition, and signature verification for updates. New fixes should include a focused regression when the behavior can recur unnoticed.

Default update configuration is intentionally disabled. Enabling it requires a Twister-owned repository or feed and a new signing key. Do not reuse another application's feed, keychain identity or signing trust.

Retain required third-party notices. Describe the user-facing change and the verification actually performed in pull requests.

## Choose a focused check

Run the regression nearest to a code change before broadening the test run. For example, `swift test --filter PDFPageEditorStateTests` checks page history, while `swift test --filter ImageAnnotationEditorStateTests` checks annotation transactions. Documentation-only changes need valid links, accurate examples and `git diff --check`; they do not require rewriting application tests.

## Prepare test fixtures

Run `python3 scripts/setup-test-fixtures.py` before the full Swift suite in a fresh checkout. The helper fetches the archive and image fixtures with pinned content hashes. Generated fixtures stay outside version control, so a successful local test run should leave `git status --short` clean.

## Verify the packaged app

After building, run the checks against the packaged executable as well as the development binary. This catches resource lookup and bundle configuration problems that a checkout can hide.

```sh
python3 scripts/audit-release.py build/Twister.app
python3 scripts/test-native-ui.py --app build/Twister.app/Contents/MacOS/Twister --output build/packaged-native-ui
python3 scripts/test-workflows.py --app build/Twister.app/Contents/MacOS/Twister --output build/packaged-workflows
```

These outputs belong under the ignored `build` directory. Keep generated app bundles, captures and personal fixtures out of commits.
