#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/tool-pins.sh
mkdir -p Tools Downloads
twister_unpack=""
trap '[[ -n "$twister_unpack" ]] && rm -rf -- "$twister_unpack"' EXIT
for component in ffmpeg ffprobe; do
  if [[ -f "Tools/$component" ]] && twister_verify_tool "$component" "Tools/$component" 2>/dev/null; then continue; fi
  archive="Downloads/$component.zip"
  # Nothing is unpacked from an archive whose checksum differs.
  if [[ ! -f "$archive" || "$(twister_sha256 "$archive")" != "${twister_archive_sha256[$component]}" ]]; then
    rm -f -- "$archive"
    "${twister_curl[@]}" "https://www.osxexperts.net/${component}9arm.zip" --output "$archive"
  fi
  if [[ "$(twister_sha256 "$archive")" != "${twister_archive_sha256[$component]}" ]]; then
    print -u2 "Checksum mismatch for the $component download; nothing was unpacked."; exit 1
  fi
  twister_unpack=$(mktemp -d "${TMPDIR:-/tmp}/twister-tools.XXXXXX")
  ditto -xk "$archive" "$twister_unpack"
  # Only the verified executable leaves the temporary folder.
  twister_verify_tool "$component" "$twister_unpack/$component"
  chmod 755 "$twister_unpack/$component"
  mv -f -- "$twister_unpack/$component" "Tools/$component"
  rm -rf -- "$twister_unpack"; twister_unpack=""
done
if [[ -d Tools/LibreOffice.app ]] && ! { twister_verify_developer_id Tools/LibreOffice.app "$twister_libreoffice_team" && twister_verify_libreoffice_version Tools/LibreOffice.app; } 2>/dev/null; then
  print -u2 "Tools/LibreOffice.app is not a validly signed LibreOffice $twister_libreoffice_version; replacing it."
  rm -rf -- Tools/LibreOffice.app
fi
if [[ ! -d Tools/LibreOffice.app ]]; then
  task_lo_source=${TWISTER_LIBREOFFICE_SOURCE:-/Applications/LibreOffice.app}
  if [[ ! -d "$task_lo_source" ]]; then print -u2 "Set TWISTER_LIBREOFFICE_SOURCE to a local LibreOffice $twister_libreoffice_version bundle, then rerun."; exit 1; fi
  twister_verify_developer_id "$task_lo_source" "$twister_libreoffice_team"
  twister_verify_libreoffice_version "$task_lo_source"
  ditto "$task_lo_source" Tools/LibreOffice.app
  twister_verify_developer_id Tools/LibreOffice.app "$twister_libreoffice_team"
  twister_verify_libreoffice_version Tools/LibreOffice.app
fi
Tools/ffmpeg -version | head -1
Tools/LibreOffice.app/Contents/MacOS/soffice --version
