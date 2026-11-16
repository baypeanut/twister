# Twister

Native file tools for macOS. Convert, edit and prepare images, PDFs, documents, audio and video without moving between separate apps.

**Apple Silicon · macOS 13 or later · English and Turkish**

![Twister workspace](docs/screenshots/workspace-light.png)

## Features

- Convert individual files or batches using formats supported by the current selection.
- Crop, resize, annotate and frame images, create collages and remove metadata.
- Organize, merge and split PDFs. Undo and redo up to 50 page or annotation edits.
- Preview and trim audio and video, adjust selection endpoints and export clips.
- Choose a saved output folder or keep results beside the original files.
- Save an operation with its options as a preset and run it again from the workspace, Finder or the command line.
- Send files from Finder through the Services menu.
- Search recent results in Library, preview them and use them in another operation.
- Carry files between apps with Float.

Optional extras, both off until you turn them on in Settings → General: web downloads from public media links, which install their own tools, and window arrangement, which keeps working but is no longer being extended.

File conversion and editing run on your Mac. Original files are preserved and output names avoid collisions. Each file of a batch is exported by itself: a file that fails leaves nothing unfinished behind, and the files that succeeded stay in place. Operations that combine their inputs, such as merging PDFs or joining videos, finish as a whole or not at all. Web downloads and optional tool setup require a network connection.

## Build and run

Install Xcode with Swift 6, Python 3 and Node.js 22 or later. Run the setup commands from the repository folder:

```sh
git clone https://github.com/baypeanut/twister.git
cd twister
scripts/setup-exiftool.sh
python3 scripts/setup-resources.py
scripts/build-app.sh release
open build/Twister.app
```

The application is created at `build/Twister.app`. Dependency resources are downloaded from pinned sources and verified with SHA-256. The in-app setup screen installs the Media and Office tools when needed and, separately, the optional Web download tools; each group can be removed again by itself. `TWISTER_WEB_DOWNLOADS=0 scripts/build-app.sh release` builds a copy without the web downloader.

Local builds use an ad-hoc signature. There is no notarized installer or configured automatic update channel yet.

## Daily use

Choose files, drop them into the workspace or paste supported clipboard content. Pick a quick conversion or open the tools menu. Available formats must support every selected file, and tools can differ between single-file and batch selections. The output folder appears above the file actions and in editor footers.

Click the menu-bar icon to open Twister. Click it again, press Escape or switch to another app to dismiss the workspace. Background operations continue when the interface is hidden, and Twister can notify you when one finishes.

A conversion or tool started while another task is running waits in a queue. A batch lists each file as waiting, working, done or failed with its reason; a summary such as "7 of 9 done, 2 failed" offers **Retry failed** for the failed files only. Library records the files that succeeded.

### Presets

**Save as preset…**, the bookmark button in an editor footer and in the EPUB options, keeps the tool with the options you chose. Settings → Formats saves a conversion with that format's settings. A preset can follow the current output folder, always save beside the originals or always save to one folder. The workspace lists the presets that fit the selected files under **Presets**; Settings → Presets lists all of them. Each can be run, renamed, duplicated, moved up or down and deleted. A password typed for a protected file is never saved in a preset.

### Finder

Select files in Finder and open **Services** from the context menu or the Finder menu: **Open in Twister** sends them to the workspace, **Convert with Twister…** opens the conversion wheel for them and **Run Twister Preset…** lists the presets that fit. macOS lists the entries once it has registered the app, normally the first time Twister is opened. If they are missing or you want a keyboard shortcut for one, turn them on in System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders.

| Action | Shortcut |
| --- | --- |
| Choose files | ⌘O |
| Paste files, an image, text or a link | ⌘V |
| Library | ⌘2 |
| Search Library | ⌘F |
| Undo / redo a PDF or annotation edit | ⌘Z / ⇧⌘Z |
| Play / pause media preview | Space |
| Mark selection start / end | I / O |
| Settings | ⌘, |
| Minimize | ⌘M |
| Dismiss workspace | Escape |

While dragging files in Finder, Shift opens conversions, Command opens tools and Control opens file actions. These shortcuts are configurable. Finder gestures and the optional window arrangement use the relevant macOS permissions; choosing files in the workspace remains available independently.

## Command line

```sh
swift build --product twister-cli
.build/debug/twister-cli catalog
.build/debug/twister-cli convert png "holiday photo.jpg"
.build/debug/twister-cli inspect photo.png
```

The CLI supports `convert`, `tool`, `preset`, `inspect`, `dependencies`, `catalog` and JSON options. With the optional runtimes installed, `twister-cli dependencies` prints the resolved conversion-tool paths; a missing dependency returns an error. The app and CLI have separate executable names so both can be built on the default macOS filesystem. Add `--json` to a conversion or tool command to print the output paths as a JSON array:

```sh
.build/debug/twister-cli convert png photo.jpg --json
```

Each file of a batch is exported by itself. The paths of the finished files go to standard output, and each failed file is reported on standard error as `PATH: reason`.

Presets are shared with the app. They are stored in `~/Library/Application Support/Twister/Presets.json`; set `TWISTER_PRESETS_FILE` to use another file.

```sh
.build/debug/twister-cli preset list
.build/debug/twister-cli preset run "Web JPEG" --json -- photo.png "--odd name.png"
.build/debug/twister-cli preset export "Web JPEG" > web-jpeg.json
.build/debug/twister-cli preset import web-jpeg.json
```

`preset list` prints each name with its operation, and `preset list --json` prints every preset in the format `export` and `import` use. `preset run` accepts `--options`, `--json` and `--` like `convert`, uses the same exit statuses and saves where the preset says; `--options` changes the saved options for that run only. `import` adds presets without replacing any: a name that is already taken gets a number. A preset is not run when its name is unknown or its folder is missing, and the command exits with 1.

| Exit status | Meaning |
| --- | --- |
| 0 | Every file was exported |
| 1 | Nothing was exported |
| 3 | Some files failed; the other exports were kept and printed |
| 64 | Usage error |
| 130, 143 | Interrupted by Ctrl-C or `kill`; exports that had already finished are kept |

## Guides

- [Getting started](docs/guide/getting-started.md)
- [Working with images](docs/guide/images.md)
- [Working with PDFs](docs/guide/pdfs.md)
- [Working with media](docs/guide/media.md)
- [Working with documents](docs/guide/documents.md)
- [Working with archives](docs/guide/archives.md)
- [Library and Float](docs/guide/library.md)
- [Optional tools](docs/guide/setup.md)
- [Troubleshooting](docs/guide/troubleshooting.md)

## Development and verification

```sh
swift build --product Twister
python3 scripts/setup-test-fixtures.py
swift test --parallel
python3 scripts/test-product-identity.py
python3 scripts/test-native-ui.py
python3 scripts/test-workflows.py
python3 scripts/test-web-download-integration.py
python3 scripts/generate-localizations.py --check
```

The full conversion suite requires FFmpeg, FFprobe, ExifTool and LibreOffice. Native interface tests need a logged-in macOS desktop. Provider-specific live tests are opt-in.

See the [development guide](CONTRIBUTING.md), [dependency setup](docs/dependencies.md) and [native verification guide](docs/testing/UI-AUDIT.md) for details.
