# Native macOS behavior  -  0.1.1

Twister is a menu-bar file utility. Its workspace should be quick to open and easy to dismiss, while file operations continue safely in the background.

## Focus and windows

- Left-click the menu-bar icon to open or dismiss the workspace. Right-click or Control-click for its commands.
- Switching to another application, changing desktops or locking the session dismisses the workspace and transient overlays. Escape dismisses the workspace when a text field is not editing.
- Dismissal orders the existing view out; it does not close the view, clear the selection, cancel a job or rewrite Library history.
- Editors, settings, downloads, onboarding and previews use normal-level native windows that hide on application deactivation. Editors have the standard close, minimize and zoom controls.
- Window commands include Hide, Hide Others, Show All, Minimize, Zoom, Close and Bring All to Front. Opening a minimized window restores it.
- Window positions use stable autosave names and are constrained to a usable display area on restoration.
- The explicitly invoked Float shelf remains a cross-application file shelf. Ordinary work windows do not use its always-visible behavior.

Apple's [panel guidance](https://developer.apple.com/design/human-interface-guidelines/panels) recommends hiding app panels when the application becomes inactive. Twister's window policy and dismissal controller apply that behavior without destroying editing state.

## Quiet operation and first run

Progress and completion overlays do not appear over an inactive application or follow it into other desktops. In-progress work remains available from the menu-bar workspace. Media previews pause when the application loses focus.

Finishing or skipping the welcome tour opens the workspace immediately. Media and Office runtimes are optional downloads available through Finish setup; missing runtimes no longer force the setup window over the workspace.

Window arrangement is off by default. Enabling it starts its observer; disabling Twister or window arrangement stops that observer. Existing explicit preferences are respected.

## Verification

`--window-lifecycle-smoke OUTPUT` uses isolated preferences and generated files in its own process. Its 28 assertions cover window levels and controls, native titlebar close-button duplication, app/Space/session notifications, view and source preservation, an uncancelled background token, Library persistence, minimize/reopen, Escape, observer cleanup and opt-in monitoring. It does not claim to synthesize external-application clicks.

The fixture is part of `scripts/test-native-ui.py`, alongside 48 gallery captures, media accessibility, artwork, setup and Float checks. Both development and packaged builds run this suite. On 27 October 2026 the user confirmed that clicking another application (Safari) dismisses the installed 0.1.1 workspace. The Computer Use bridge had intermittent target-app errors, so this external-click confirmation is attributed to the user rather than to automated input.

## Distribution status

This build is a directly distributed development application with an ad-hoc signature. It is not a submitted Mac App Store build.

A Store variant requires [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox), an appropriate Xcode archive/signing setup and an App Store submission. The optional runtime delivery and accessibility-based window arrangement also need a Store-specific design. Apple lists accessibility-based assistive operations among [sandbox-incompatible functionality](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox). Turning an option off by default does not certify the existing application for Store distribution.
