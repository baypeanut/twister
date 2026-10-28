# Window management

Twister can arrange a window while its native title bar or resize border is being dragged. Tap Shift or Command, move over a wheel slice and release the mouse. Releasing the modifier keeps the wheel open. Escape dismisses it until the next gesture.

| Width | Positions |
| --- | --- |
| One third | Left, middle, right |
| One half | Left, right |
| Two thirds | Left, right |
| Full usable area | Maximize |

Enable the feature in Settings → General → Window management and grant Twister the requested macOS window-control permission. The app has its own `app.twister.desktop` identity. It does not inherit another app's permission grants or alter the privacy database.

The destination display's usable area excludes the menu bar and Dock. Negative monitor coordinates, Retina scaling and odd widths are handled by shared geometry code. Full-screen, minimized and non-resizable windows are excluded. A window must actually move or resize before the wheel activates. File drags and editable controls take precedence.

Some applications enforce minimum sizes or reject accessibility resizing. Twister reports refused placements. Geometry regression tests cover layouts and cancellation; physical input testing requires explicit macOS permissions and generated fixture windows.
