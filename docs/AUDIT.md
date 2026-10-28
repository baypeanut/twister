# Security and verification

Twister processes local files through native macOS frameworks and optional conversion tools. The following boundaries are covered by automated regression checks.

| Area | Protection |
| --- | --- |
| Archive extraction | Validate paths and link ancestors before creating entries; enforce resource limits |
| Exports | Stage results transactionally, preserve originals and reserve unique destination names |
| Image imports | Check encoded size and dimensions before allocating raster memory |
| Subprocesses | Pass argument arrays, support cancellation and bound diagnostic capture |
| Runtime setup | Download into staging and verify pinned hashes before installation |
| Updates | Require configured repository identity and signed update metadata |
| Credentials | Use application-specific storage and reject unconfigured connections |
| Local resources | Resolve packaged resources without depending on the development checkout |

## Running checks

See [contributing](../CONTRIBUTING.md) for build and test commands, and [native verification](testing/UI-AUDIT.md) for GUI checks. The Swift suite covers conversion engines, file safety, editor history, update trust and window geometry. Native fixtures exercise exports, cancellation, recovery, keyboard routing, accessibility and window lifecycle.

Live media-provider checks require explicit opt-in and may depend on service availability. GUI checks require an unlocked macOS login session. Tests use generated fixtures and temporary output folders.

## Distribution

Local packages use an ad-hoc signature. Developer ID signing, notarization and an update-signing channel require separate release configuration. Automatic updates are disabled by default. Downloaded tools retain their component notices.

## Maintenance

Keep native dependencies and optional tools current. Review parser resource limits, untrusted HTML resource access and subprocess output limits when adding formats. Passing tests does not establish that every possible input is safe.
