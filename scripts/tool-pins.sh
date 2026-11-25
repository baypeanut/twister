#!/bin/zsh
# Source from the repository root. Pinned upstream tools; the same values are
# in Sources/TwisterCore/ExternalToolSetup.swift and checked by ToolPinTests.

typeset -gA twister_tool_sha256=(
  ffmpeg 591260c945d0eef150e3bf82b0ef988bd36a9cecc18ff05d6679617159f0a95e
  ffprobe e11c17e8200b3ee4c4c186d245e2b4053f01d56957336c1817fca0b997469106
  yt-dlp 0f192b7ec147ab6288885d6351d9ab67367640029b4377576ef46dd79cf7b202
  deno b73737579d5a84c160e3316487594783fa5c15f4e13252a6a07050b755317f1a
)
typeset -gA twister_archive_sha256=(
  ffmpeg d0c06c5c68ce48af3143b262f7a9118a7c9f67de1e237fcc24ffb14df9c67af9
  ffprobe 0c94fbdd8917022f28115eca512196cf4648732bc9e5db9ec8896c7e519d02aa
)
# Developer ID teams of upstream signatures that are kept as they are.
twister_libreoffice_team=7P5S3ZLCN7
# The LibreOffice release that is bundled and that tool setup downloads.
twister_libreoffice_version=26.8.3
twister_deno_team=2H4KBF436B
# Every download is HTTPS, including each redirect.
twister_curl=(curl --fail --location --proto '=https' --proto-redir '=https')

twister_sha256() { shasum -a 256 -- "$1" | awk '{print $1}'; }

# Fails unless the file is a regular file with the pinned hash.
twister_verify_tool() {
  local name=$1 file=$2 expected=${twister_tool_sha256[$1]:-}
  if [[ -z "$expected" ]]; then print -u2 "No pinned hash for $name."; return 1; fi
  if [[ ! -f "$file" || -L "$file" ]]; then print -u2 "$file is not a regular file."; return 1; fi
  if [[ "$(twister_sha256 "$file")" != "$expected" ]]; then print -u2 "Checksum mismatch for $file; refusing to use it."; return 1; fi
}

# Fails unless the code carries a valid Developer ID signature of the team.
twister_verify_developer_id() {
  local code=$1 team=$2
  codesign --verify --deep --strict --test-requirement "=anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"$team\"" "$code" || {
    print -u2 "$code is not validly signed by Developer ID team $team."; return 1
  }
}

# Fails unless the LibreOffice bundle is the pinned release. LibreOffice
# reports releases with a fourth build number, such as 26.8.3.2.
twister_verify_libreoffice_version() {
  local bundle=$1 version
  version=$(plutil -extract CFBundleShortVersionString raw -o - "$bundle/Contents/Info.plist" 2>/dev/null || true)
  if [[ "$version" != "$twister_libreoffice_version" && "$version" != "$twister_libreoffice_version".<-> ]]; then
    print -u2 "$bundle is LibreOffice ${version:-of an unknown version}, not the pinned $twister_libreoffice_version. Refresh Tools/LibreOffice.app as described in CONTRIBUTING.md."
    return 1
  fi
}
