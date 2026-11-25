# Security

Twister processes files locally on macOS. Documents, archives, media containers and clipboard contents are untrusted inputs. Public-link downloads and optional runtime setup make explicit network requests.

## Reporting

For sensitive reports, use the repository's private vulnerability reporting feature when available. Do not put credentials, private documents or working exploit payloads against third-party systems in public issues. A useful report includes the affected commit, a minimal safe fixture, expected behavior and actual impact.

## Boundaries

- File exports are staged before publication and avoid replacing originals.
- Archive extraction rejects traversal, unsafe links, special files and oversized archives.
- Native media subprocesses receive argument arrays and restrict nested input protocols.
- Downloaded runtimes are pinned to HTTPS URLs and SHA-256 hashes, and installed tools are verified again before use.
- Files extracted or converted from a quarantined input keep its quarantine, including read-only entries, and web downloads are quarantined, so Gatekeeper still assesses them. Files that helper tools create for their own use are not quarantined.
- Link downloads refuse this Mac and local network addresses unless the user allows them. Every connection of a download, including redirects and media addresses found inside pages, goes through a loopback proxy that resolves the destination once, refuses addresses that are not public and connects to the address it checked.
- Images are opened up to 250 megapixels, checked from their headers before decoding; previews, thumbnails and PDF page rasters are reduced to a fixed pixel budget instead.
- Update feeds and archives require signature verification. The default Twister channel is disabled until independent release trust is configured.
- Preferences, imported clipboard files, runtime storage and credential namespaces are separate from other applications.

See [the current review](docs/AUDIT.md) for fixes, evidence and remaining limitations. A successful test run is not a guarantee that every parser, codec or external service is free of defects.
