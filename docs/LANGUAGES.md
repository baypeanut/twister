# Languages

Twister supports English and Turkish. Set the language in Settings; UI copy changes while filenames, file contents, format identifiers and export parameters remain verbatim.

The canonical catalog is `Sources/TwisterCore/Resources/Turkish.json`. Regenerate SwiftUI string tables after editing:

```sh
python3 scripts/generate-localizations.py
python3 scripts/generate-localizations.py --check
```

`AppLocalizationTests` covers tool and window-layout coverage, Turkish casing, placeholders, fallback and preservation of user input. The native UI gallery captures both languages in light and dark appearance.
