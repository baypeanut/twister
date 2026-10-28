# Workflow features and roadmap

## Implemented

### Remembered output folder

Home and editor footers now offer a destination chooser. The default remains beside the originals. A selected folder is remembered through a security-scoped bookmark, and each export captures its destination before starting. Changing the preference cannot redirect a running job. An explicit destination supplied by an operation takes precedence.

A missing, stale or invalid saved folder requests a new selection; it never silently saves elsewhere. The user can restore **Beside originals**. Existing filenames continue to use transactional unique output naming, and original files remain untouched.

### PDF page Undo and Redo

The page organizer now supports Undo and Redo for rotate, duplicate, delete and move. It restores page order, source positions, rotation and selection. History retains the last 50 page edits; selecting a page does not consume an entry. A new edit clears Redo, and replacing or resetting the document clears both stacks.

Compact controls, the native Edit menu and ⌘Z / ⇧⌘Z are available in the PDF organizer. Shortcuts still work after a page-edit button has focus. Text fields and other native inputs retain their own editing behavior. History stores page references and rotations as values rather than a complete PDF copy per step.

### Quiet completion

Automatic Finder reveal is off for a fresh profile. A previously enabled preference is respected while Twister is active. A background export no longer activates Finder and interrupts the current application.

## Next candidates

These remain backlog items, not implemented features:

| Candidate | Benefit | Design constraint |
| --- | --- | --- |
| Append files to an existing selection | Assemble a batch across several drops or file dialogs | Make Add and Replace explicit; remove duplicate URLs without changing intentional order |
| Remove or clear Library entries | Keep recent work manageable | Remove references only; leave files on disk |
| Retry a failed operation | Recover without reconstructing the same job | Preserve useful options without storing passwords or other secrets in history |
| Recover failed editor preparation | Offer Retry or Setup in place | Keep the selected files and editing context intact |

## Verification

Core PDF regressions cover mixed operations, independent duplicate rotations, invalid actions, divergent edits, document replacement, bounded history and copied editor state. Native checks exercise the production shortcut router with page buttons and native inputs, native Edit-menu action routing through the production SwiftUI hosting and shortcut attachment, text-field undo and responder cleanup. Generated image exports check destination persistence, explicit overrides, a removed folder, filename collisions, immutable in-flight selection and unchanged original bytes.

The UI gallery includes the new output-folder and PDF organizer scenes in both supported languages and appearances. Release packages run the same native checks as development builds. See [native verification](testing/UI-AUDIT.md).

Local verification completed for 0.2.0:

- The 301-test Swift suite completed successfully (live media-provider tests remain opt-in).
- 48 gallery captures passed with 74 layout, input-routing and output-safety guardrails.
- 26 real output-folder checks passed, together with 28 window lifecycle, 30 range, 11 artwork, 15 setup and 16 shelf checks.
- Update configuration, release-audit regressions, localization generation and tracked-source policy checks passed.

Version 0.2.1 added transaction-based annotation Undo/Redo after reproducing the old Undo behavior deleting the wrong mark. It also fixed missing-result Library reuse, a media editor teardown crash, disabled timeline dragging, and the app/CLI filename collision on macOS.
