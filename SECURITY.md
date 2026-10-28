# Security

Twister processes files locally on macOS. Documents, archives, media containers and clipboard contents are untrusted inputs. Public-link downloads and optional runtime setup make explicit network requests.

## Reporting

For sensitive reports, use the repository's private vulnerability reporting feature when available. Do not put credentials, private documents or working exploit payloads against third-party systems in public issues. A useful report includes the affected commit, a minimal safe fixture, expected behavior and actual impact.

## Boundaries

- File exports are staged before publication and avoid replacing originals.
- Archive extraction rejects traversal, unsafe links, special files and oversized archives.
- Native media subprocesses receive argument arrays and restrict nested input protocols.
- Downloaded runtimes are pinned to HTTPS URLs and SHA-256 hashes.
- Update feeds and archives require signature verification. The default Twister channel is disabled until independent release trust is configured.
- Preferences, imported clipboard files, runtime storage and credential namespaces are separate from other applications.

See [the current review](docs/AUDIT.md) for fixes, evidence and remaining limitations. A successful test run is not a guarantee that every parser, codec or external service is free of defects.
