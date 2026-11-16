# Runtime dependencies

Twister is a native macOS application. Swift Package Manager pins Sparkle in `Package.swift` and `Package.resolved`. The app bundles license notices for libraries and conversion interop code in `Resources/licenses`.

## Native features

Standard image and PDF operations use macOS frameworks. ExifTool provides metadata support and is included from a pinned, hash-verified source archive:

```sh
scripts/setup-exiftool.sh
python3 scripts/setup-resources.py
```

## Optional tools

The setup screen installs each tool group by itself after the user chooses a download. Existing usable tools are discovered first. Every download is SHA-256 checked before anything is read from it; an executable taken from an archive is checked a second time, and a group is published only after verification. Cancellation keeps completed installations intact.

| Group | Tool | Role |
| --- | --- | --- |
| Media | FFmpeg / FFprobe | Media conversion, inspection, previews and additional image formats |
| Office | LibreOffice | Office document conversion |
| Web (optional) | yt-dlp | Public media-link downloads |
| Web (optional) | Deno | Script runtime used by supported media extractors |
| Bundled | ExifTool | Metadata inspection and editing |

Media conversion needs the Media group only. Web downloads are opt-in: they need the Web group, and FFmpeg from the Media group to merge and convert what was downloaded. Until the user decides, the **Web downloads** setting follows whether the Web tools are present.

Setup shows where each group was found (downloaded by Twister, inside the app, a `TWISTER_` override or elsewhere on the computer) and, for its own downloads, the pinned version and the size on disk. **Remove** deletes only what setup downloaded for that group: `media-v1/ffmpeg` and `media-v1/ffprobe`, `web-v1` together with the `yt-dlp` and `deno` an earlier setup stored in `media-v1`, or `office-26.8.1`. Paths are checked against the real location of the tool folder, a link is unlinked and never followed, and a file that an override points at stays in place. Homebrew tools and the tools inside the app bundle are never removed.

### Building without the web downloader

```sh
TWISTER_WEB_DOWNLOADS=0 scripts/build-app.sh release
```

The script writes `TwisterWebDownloads = false` to the bundle's `Info.plist` and leaves yt-dlp and Deno out of a bundle that carries its tools. Such a copy has no download entry in the menus, the workspace, the link wheel, Settings or setup, and registers no download shortcut. The default, and any build made without the variable, includes the downloader.

Exact versions, upstream URLs, sizes and hashes live in `Sources/TwisterCore/ExternalToolSetup.swift`, `scripts/setup-exiftool.sh` and the setup scripts. Tool storage is `~/Library/Application Support/Twister/Tools`. Overrides use `TWISTER_FFMPEG`, `TWISTER_FFPROBE`, `TWISTER_SOFFICE` and `TWISTER_EXIFTOOL`.

The FFmpeg and FFprobe archives come from an address without a version in its path. Their archive checksums were taken from the files that contain the pinned executables; if the publisher repacks an archive, setup stops with a checksum error until the pins are updated.

FFmpeg builds and yt-dlp may carry GPL obligations; LibreOffice and bundled components retain their respective licenses. Consult [third-party notices](../Resources/THIRD-PARTY-NOTICES.txt) before distributing a package with additional runtimes.

## Updates and signing

Local builds are ad-hoc signed. Automatic updates are disabled in both default configuration files. Preparing a signed update requires an independently configured Twister feed and key. Developer ID signing and Apple notarization are separate release steps and are not supplied by this repository.
