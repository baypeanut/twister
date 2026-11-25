# Security and verification

Twister processes local files through native macOS frameworks and optional conversion tools. The following boundaries are covered by automated regression checks.

| Area | Protection |
| --- | --- |
| Archive extraction | Validate paths and link ancestors before creating entries; resolve every link on disk; enforce resource limits, with smaller limits for document packages |
| Quarantine | Keep the input's quarantine on extracted and converted outputs, including read-only entries; quarantine web downloads; leave files that helper tools create for themselves unquarantined |
| Exports | Stage results transactionally, preserve originals and reserve unique destination names |
| Image imports | Check encoded size and declared dimensions (250 megapixels) before allocating raster memory, also in the FFmpeg fallback decoder; draw vector images at exactly the checked size; reduce previews, thumbnails and every PDF raster to a pixel budget instead of refusing them |
| Link downloads | Refuse loopback, private and local-network hosts, including redirects; route the extractor and direct transfers through a per-download loopback proxy that resolves each destination once, refuses non-public addresses and connects to the checked address; ignore proxy settings from the environment; name files after their detected content |
| Subprocesses | Pass argument arrays, support cancellation and bound diagnostic capture |
| Runtime setup | Download into staging and verify pinned hashes or the publisher signature before installation; check each tool again before its first use in a session and after any change to the file, and the office bundle's signature before every use; bundle only the pinned LibreOffice release |
| Updates | Require configured repository identity and signed update metadata |
| Credentials | Use application-specific storage and reject unconfigured connections |
| Local resources | Resolve packaged resources without depending on the development checkout |

## Running checks

See [contributing](../CONTRIBUTING.md) for build and test commands, and [native verification](testing/UI-AUDIT.md) for GUI checks. The Swift suite covers conversion engines, file safety, editor history, update trust and window geometry. Native fixtures exercise exports, cancellation, recovery, keyboard routing, accessibility and window lifecycle.

Live media-provider checks require explicit opt-in and may depend on service availability. GUI checks require an unlocked macOS login session. Tests use generated fixtures and temporary output folders.

## Distribution

Local packages use an ad-hoc signature with the hardened runtime. Packages without update support carry no updater framework and keep library validation; only update-enabled ad-hoc or locally signed packages disable it for that framework. The bundled yt-dlp alone disables it, for the Python runtime it unpacks. Developer ID signing, notarization and an update-signing channel require separate release configuration. Automatic updates are disabled by default. Downloaded tools retain their component notices.

## Maintenance

Keep native dependencies and optional tools current. Review parser resource limits, untrusted HTML resource access and subprocess output limits when adding formats. Passing tests does not establish that every possible input is safe.
