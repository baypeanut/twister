# Publishing Twister

Stable releases are published from version tags, not ordinary pushes. No Apple
Developer membership is needed for the current community distribution.

## Publish a version

1. Merge the changes into `main` and wait for Source checks to pass.
2. Add optional user-facing notes at `docs/releases/0.3.1.md` and commit them.
3. Tag the commit and push the tag:

```sh
git tag -a v0.3.1 -m "Twister 0.3.1"
git push origin v0.3.1
```

The Publish Twister workflow checks that the commit belongs to `main`, rejects
old or reused versions, and runs the complete source checks. It then builds the
Apple silicon app, checks the packaged interface and workflows, signs the archive
and appcast, uploads everything to a draft release, and publishes it as latest.
A failed check prevents publication. An incomplete draft never becomes the
public update feed. If an upload fails, inspect and delete that unpublished draft
before retrying; never replace assets in an already published release.

Only `vMAJOR.MINOR.PATCH` tags are accepted. Each component is 0 through 999.
The build number is `MAJOR * 1000000 + MINOR * 1000 + PATCH`, so moving to the
next version always advances Sparkle's version comparison. To undo a faulty
release, revert its code and publish a higher version; do not move old tags.

## Signing and trust

`Configuration/Updates.public.plist` contains the public Ed25519 key and the
anonymous GitHub release feed. The corresponding private key is held in the
repository secret `TWISTER_UPDATE_PRIVATE_KEY`. It is written to a restricted
temporary file only in the publishing job and removed at the end. Keep an offline
backup of this key. Losing it can prevent existing installations from accepting
future updates. Do not rotate it by simply replacing the public key.

Both the feed and archive must pass Sparkle signature verification. The app also
uses an ad-hoc code signature and the hardened runtime. This is not an Apple
Developer ID signature and the app is not notarized. macOS may block the first
launch. Download only from the official release, move the app to Applications,
then use System Settings > Privacy & Security > Open Anyway if needed.

No GitHub login or token is required in the app. The public feed is:

`https://github.com/baypeanut/twister/releases/latest/download/appcast.xml`

## Local verification

Ordinary `scripts/build-app.sh release` builds stay disconnected from the public
update channel. To prepare the same package as the release workflow:

```sh
swift package resolve
export TWISTER_SIGNING_MODE=ad-hoc
export TWISTER_COMMUNITY_RELEASE=1
export TWISTER_UPDATE_KEY_FILE=/secure/path/to/update-signing.key
scripts/prepare-public-release.sh 0.3.1 3001
```

The output is under `build/public-upload-0.3.1-3001`. Versioned archives are
immutable. The additional `Twister-macOS-arm64.zip` asset is the convenient manual
download; `appcast.xml` points at the versioned archive. SHA256SUMS accompanies
the assets for manual integrity checks.

Run `python3 scripts/test-update-install.py` in a logged-in macOS session to test
real installation and relaunch, modified-feed rejection, and modified-archive
rejection. The test uses disposable apps, preferences and signing keys; it does
not update the installed Twister or use its release key.

The first update-enabled release must be installed manually over older local
builds. Subsequent releases are checked while the app runs, approximately hourly.
Users can turn off automatic checks or check manually from Settings > Updates.
Downloads and installation require user action. Preferences, presets and external
tools are stored outside the app bundle and are preserved across updates.
