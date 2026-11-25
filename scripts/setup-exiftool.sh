#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/tool-pins.sh
revision=2200871d9cef988051d2a99d67df3bda6cbb30a8
expected=e1e2ad6c6fbf568afee5993ef8b2b91ab013d21698c9304e079e633ad82776f5
mkdir -p Downloads Tools
archive=Downloads/exiftool-13.59.tar.gz
if [[ ! -f "$archive" || "$(twister_sha256 "$archive")" != "$expected" ]]; then
  rm -f -- "$archive"
  "${twister_curl[@]}" "https://codeload.github.com/exiftool/exiftool/tar.gz/$revision" --output "$archive"
fi
if [[ "$(twister_sha256 "$archive")" != "$expected" ]]; then print -u2 'ExifTool checksum mismatch'; exit 1; fi
# Always unpack the verified archive again, so files added to or changed in
# an earlier copy never reach the app.
staging=$(mktemp -d "$PWD/Tools/.ExifTool.XXXXXX")
trap 'rm -rf -- "$staging"' EXIT
tar -xzf "$archive" --strip-components=1 --no-same-owner -C "$staging"
rm -rf -- Tools/ExifTool
mv -- "$staging" Tools/ExifTool
chmod 755 Tools/ExifTool
/usr/bin/perl Tools/ExifTool/exiftool -config '' -ver
