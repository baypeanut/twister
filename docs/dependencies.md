# Runtime dependencies

Twister is a native macOS application. Swift Package Manager pins Sparkle in `Package.swift` and `Package.resolved`. The app bundles license notices for libraries and conversion interop code in `Resources/licenses`.

## Native features

Standard image and PDF operations use macOS frameworks. ExifTool provides metadata support and is included from a pinned, hash-verified source archive:

```sh
scripts/setup-exiftool.sh
python3 scripts/setup-resources.py
```

## Optional tools

The setup screen installs missing media and Office groups after the user chooses a download. Existing usable tools are discovered first. Downloads are staged, SHA-256 checked and published only after verification; cancellation keeps completed installations intact.

| Tool | Role |
| --- | --- |
| FFmpeg / FFprobe | Media conversion, inspection, previews and additional image formats |
| yt-dlp | Public media-link downloads |
| Deno | Script runtime used by supported media extractors |
| LibreOffice | Office document conversion |
| ExifTool | Metadata inspection and editing |

Exact versions, upstream URLs, sizes and hashes live in `Sources/TwisterCore/ExternalToolSetup.swift`, `scripts/setup-exiftool.sh` and the setup scripts. Tool storage is `~/Library/Application Support/Twister/Tools`. Overrides use `TWISTER_FFMPEG`, `TWISTER_FFPROBE`, `TWISTER_SOFFICE` and `TWISTER_EXIFTOOL`.

FFmpeg builds and yt-dlp may carry GPL obligations; LibreOffice and bundled components retain their respective licenses. Consult [third-party notices](../Resources/THIRD-PARTY-NOTICES.txt) before distributing a package with additional runtimes.

## Updates and signing

Local builds are ad-hoc signed. Automatic updates are disabled in both default configuration files. Preparing a signed update requires an independently configured Twister feed and key. Developer ID signing and Apple notarization are separate release steps and are not supplied by this repository.
