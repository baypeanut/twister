# Twister design

Twister is a focused macOS utility. The interface uses a persistent navigation rail, a single file workspace and a separate recent-file library. File selection always comes before tool selection; formats and tools come from the actual selection.

## Visual language

- Warm paper surfaces, charcoal text and a restrained burnt-sienna accent.
- A serif headline gives the workspace its identity; system typography keeps controls familiar.
- Flat buttons, small corner radii, thin dividers and deliberate spacing replace decorative surfaces.
- A geometric folded-strip mark is drawn from the same vector for the app, menu bar and onboarding. No mascot or generated imagery is used.
- Dark appearance uses the same hierarchy, with warm dark surfaces and lighter secondary text.

The main window supports a 700 × 580 content area. Long file names wrap or truncate inside their row; they never replace the sidebar. The workspace and library scroll independently of navigation. Editors retain separate preview, options and action regions.

## Interaction

Native open panels, drag and drop, clipboard import, Finder gestures, contextual menus and keyboard shortcuts remain available. Selection actions are generated from supported operations rather than decorative placeholders. A conversion or tool started while another task runs waits in a queue and starts by itself; moving, sharing and Library reuse stay disabled until the running task ends. A batch lists its files with their status, and a file that failed shows its reason beside a retry for the failed files only. Reduced Motion preferences are respected; hover feedback does not shift content.

A preset is a saved operation with its options and an optional destination. Presets are saved from the place where the options are chosen, and the workspace offers only the presets the catalog allows for the current selection. Twister ships no sample presets. The Services menu entries follow the same rule: a request that cannot act on the files says why instead of opening an empty chooser.

English and Turkish copy share one catalog. User file names and paths remain verbatim. Icons that accompany text are decorative; icon-only actions retain accessible labels.

## Shortcuts actions

Twister has no actions in the Shortcuts app. An action is found through `Metadata.appintents` in the bundle, which Xcode's build writes and `scripts/build-app.sh` does not.

A probe outside this repository showed that the file can be produced from a SwiftPM build with Xcode 26: the app target is compiled with `-emit-const-values` and `-const-gather-protocols-file`, and `xcrun appintentsmetadataprocessor` turns the resulting `.swiftconstvalues` files into a metadata bundle that describes the intent and its file parameters. Two things keep this out of the build:

- The list of protocols to gather and the arguments of the processor belong to Xcode's build system. Neither is documented, and the list is not shipped as a file, so a copy kept here could go stale with an Xcode update and silently produce an incomplete action list.
- It is not established that Shortcuts lists and runs the actions of a bundle made this way. An ad-hoc signed probe bundle registered with Launch Services had not reached the Shortcuts tool index a minute later, and running an action was not tried.

Building the app target with Xcode, with this package as its dependency and `xcodebuild archive` in place of the hand-assembled bundle, makes the metadata step a supported part of the build. The intents themselves would call `ConversionEngine.runBatch` and `PresetStore` directly, as `twister-cli` does. Until then, **Run Shell Script** in Shortcuts can call `twister-cli convert` or `twister-cli preset run`, and the Finder services cover the same operations from the Services menu.
