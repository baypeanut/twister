# Native macOS verification

The UI audit launches Twister's own windows using generated files and isolated preferences. It does not start production global hotkeys, clipboard import, window management or the update loop.

```sh
swift build --product Twister
python3 scripts/test-native-ui.py
```

The check creates an ad-hoc-signed audit bundle, rejects unsafe output destinations and invalid arguments, then captures twelve scenes in English/Turkish and light/dark appearance: empty Home, selected Home, Home with an output folder, Library, three Settings sections, the PDF tools wheel a PDF page organizer and three image editors. The Settings scenes carry the production toolbar tabs; a capture fails when the selected tab or the window title does not match its pane. It also validates editor bounds, media selection accessibility, asynchronous artwork loading, first-run setup cancellation/retry, the floating shelf and 28 window lifecycle assertions. PDF history shortcut checks cover focused page buttons while preserving native field input. Real generated image exports validate output-folder persistence, collision handling, missing folders and source preservation. A GUI login session is required.

Screenshots and manifests are written under ignored `build/native-ui`. The manifest must report success for all 48 captures. Native preview captures demonstrate rendered state; they do not replace conversion, gesture or OS-permission tests.

To capture a smaller review set:

```sh
build/Twister.app/Contents/MacOS/Twister --ui-audit build/design-review --scenes home.empty,home.selected,library --appearance both --language en
```

Scenes outside the gallery can be captured by name for review: `home.batch`, `settings.presets`, `settings.compatibility`, `settings.folders`, `tool.compress`, `setup`, `download`, `welcome`, `epub`, `preset.picker`, `toast.success` and `toast.progress`. They are not part of the 48 captures.

The destination must be empty or marked as an existing audit-owned directory. The audit refuses to overwrite unrelated files.

Application workflow regressions also exercise real image/PDF/audio/video exports, a corrupt file failing alone in its batch, retry of only that file, queued tasks, cancellation recovery, missing Library entries and eight production editor lifecycles. They require FFmpeg and FFprobe on PATH or configured tool paths:

```sh
python3 scripts/test-workflows.py
python3 scripts/test-product-identity.py
python3 scripts/test-web-download-integration.py
```

The product identity check builds both executable products and verifies the CLI cannot replace the application on a case-insensitive macOS filesystem. Web-download integration uses a local fixture server and checks conversion, progress, collision handling and cancellation cleanup.
