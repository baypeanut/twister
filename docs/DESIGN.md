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

Native open panels, drag and drop, clipboard import, Finder gestures, contextual menus and keyboard shortcuts remain available. Selection actions are generated from supported operations rather than decorative placeholders. A disabled action stays disabled while a file job runs. Reduced Motion preferences are respected; hover feedback does not shift content.

English and Turkish copy share one catalog. User file names and paths remain verbatim. Icons that accompany text are decorative; icon-only actions retain accessible labels.
