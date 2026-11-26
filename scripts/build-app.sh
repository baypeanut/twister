#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration=${1:-release}
# Resource notices must be generated from the verified tool, including on a fresh runner.
scripts/setup-exiftool.sh >/dev/null
python3 scripts/setup-resources.py
source scripts/signing-configuration.sh
source scripts/tool-pins.sh
twister_load_signing_configuration
twister_selected_update_config=${TWISTER_UPDATE_CONFIG:-Configuration/Updates.plist}
twister_public_build=false
# TWISTER_WEB_DOWNLOADS=0 builds a copy without the web downloader: no entry
# point in the interface and no yt-dlp or Deno in the bundle. Default: included.
twister_web_downloads=true
case "${TWISTER_WEB_DOWNLOADS:-1}" in
  1|true|yes|on) ;;
  0|false|no|off) twister_web_downloads=false ;;
  *) print -u2 "TWISTER_WEB_DOWNLOADS must be 1 or 0"; exit 1 ;;
esac
twister_bundled_tools=(ffmpeg ffprobe)
if [[ "$twister_web_downloads" == true ]]; then twister_bundled_tools+=(yt-dlp deno); fi
if [[ -f "$twister_selected_update_config" ]] && { plutil -type PublicRepository "$twister_selected_update_config" >/dev/null 2>&1 || [[ "$(plutil -extract ExternalTools raw -o - "$twister_selected_update_config" 2>/dev/null || true)" == true ]]; }; then twister_public_build=true; fi
# The bundle's Info.plist, with update trust applied, decides whether the
# updater is part of this build. Without an update signing key the updater can
# never start, so its framework is neither linked nor embedded, and the app
# keeps full library validation.
twister_info_directory=$(mktemp -d /tmp/twister-info.XXXXXX)
cp Resources/Info.plist "$twister_info_directory/Info.plist"
python3 scripts/configure-updates.py "$twister_info_directory/Info.plist" "${TWISTER_UPDATE_CONFIG:-Configuration/Updates.plist}"
twister_updates=false
if plutil -extract SUPublicEDKey raw -o - "$twister_info_directory/Info.plist" >/dev/null 2>&1; then twister_updates=true; fi
twister_swift_flags=()
if [[ "$twister_updates" == false ]]; then twister_swift_flags=(-Xswiftc -DTWISTER_WITHOUT_UPDATES -Xlinker -dead_strip_dylibs); fi
# SwiftPM also embeds a literal fallback resource path, which compiler prefix
# maps do not rewrite. Build in a private temporary directory outside the home
# folder, then prove the packaged app works after this directory is removed.
twister_build_directory=$(mktemp -d /tmp/twister-swift.XXXXXX)
# zsh skips EXIT traps when errexit leaves from inside a function, so the
# checks below that are functions exit explicitly.
trap 'rm -rf -- "$twister_build_directory" "$twister_info_directory"' EXIT
swift build --scratch-path "$twister_build_directory" -c "$configuration" --product Twister -Xswiftc -file-prefix-map -Xswiftc "$PWD=/twister" -Xswiftc -file-compilation-dir -Xswiftc /twister "${twister_swift_flags[@]}"
binary_dir=$(swift build --scratch-path "$twister_build_directory" -c "$configuration" --show-bin-path)
application=${TWISTER_APP_OUTPUT:-"$PWD/build/Twister.app"}
sparkle_root="$twister_build_directory/artifacts/sparkle/Sparkle"
sparkle_framework="$sparkle_root/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ "$twister_updates" == true && ! -d "$sparkle_framework" ]]; then print -u2 "Missing Sparkle framework; run swift package resolve"; exit 1; fi
if [[ "$twister_updates" == false ]] && otool -L "$binary_dir/Twister" | grep -q 'Sparkle.framework'; then
  print -u2 "A build without updates must not link the updater framework."; exit 1
fi
if [[ -f "$application/Contents/Info.plist" ]]; then
  existing_identifier=$(plutil -extract CFBundleIdentifier raw -o - "$application/Contents/Info.plist")
  expected_identifier=$(plutil -extract CFBundleIdentifier raw -o - Resources/Info.plist)
  if [[ "$existing_identifier" != "$expected_identifier" ]]; then print -u2 "Refusing to overwrite a different application at $application"; exit 1; fi
fi
# Twister uses its own Keychain service and never carries an inherited broker.
if [[ -e "$application/Contents/XPCServices/local.twister.replica.credentials.v1.xpc" ]]; then
  print -u2 "Use a fresh output directory; this output contains an incompatible credential broker."
  exit 1
fi
mkdir -p "$application/Contents/MacOS" "$application/Contents/Resources/Tools"
cp "$binary_dir/Twister" "$application/Contents/MacOS/Twister"
if [[ "$configuration" == release ]]; then /usr/bin/strip -S "$application/Contents/MacOS/Twister"; fi
cp "$twister_info_directory/Info.plist" "$application/Contents/Info.plist"
python3 scripts/generate-localizations.py
ditto Resources/Localizations "$application/Contents/Resources"
if [[ -d "$binary_dir/Twister_TwisterCore.bundle" ]]; then ditto "$binary_dir/Twister_TwisterCore.bundle" "$application/Contents/Resources/Twister_TwisterCore.bundle"; fi
if [[ "$twister_web_downloads" == false ]]; then
  plutil -replace TwisterWebDownloads -bool false "$application/Contents/Info.plist"
  rm -f -- "$application/Contents/Resources/Tools/yt-dlp" "$application/Contents/Resources/Tools/deno"
fi
if [[ -d "$application/Contents/Frameworks/Sparkle.framework" ]]; then rm -rf "$application/Contents/Frameworks/Sparkle.framework"; fi
rm -f -- "$application/Contents/Resources/licenses/Sparkle-LICENSE.txt"
if [[ "$twister_updates" == true ]]; then
  mkdir -p "$application/Contents/Frameworks"
  ditto "$sparkle_framework" "$application/Contents/Frameworks/Sparkle.framework"
else
  rmdir "$application/Contents/Frameworks" 2>/dev/null || true
fi
if [[ "$twister_public_build" == true ]]; then
  if [[ -e "$application/Contents/Resources/Tools/ffmpeg" || -d "$application/Contents/Resources/Tools/LibreOffice.app" ]]; then
    print -u2 'Public packages require a fresh output directory without bundled third-party runtimes.'; exit 1
  fi
  plutil -replace TwisterExternalTools -bool true "$application/Contents/Info.plist"
else
for component in "${twister_bundled_tools[@]}"; do
  if [[ ! -x "Tools/$component" ]]; then print -u2 "Missing Tools/$component; see scripts/setup-tools.sh and scripts/setup-web-download-tools.py"; exit 1; fi
  # Only the pinned upstream executables are signed into the app.
  twister_verify_tool "$component" "Tools/$component" || exit 1
  cp "Tools/$component" "$application/Contents/Resources/Tools/$component"
  twister_verify_tool "$component" "$application/Contents/Resources/Tools/$component" || exit 1
done
fi
# A fresh copy from the archive verified before resource generation.
rm -rf -- "$application/Contents/Resources/Tools/ExifTool"
ditto Tools/ExifTool "$application/Contents/Resources/Tools/ExifTool"
# TWISTER_BUNDLED_OFFICE=0 leaves LibreOffice out of a build with bundled
# tools, for checking the other tools while Tools/ holds another release.
twister_bundled_office=true
case "${TWISTER_BUNDLED_OFFICE:-1}" in
  1|true|yes|on) ;;
  0|false|no|off) twister_bundled_office=false ;;
  *) print -u2 "TWISTER_BUNDLED_OFFICE must be 1 or 0"; exit 1 ;;
esac
if [[ "$twister_public_build" == false ]]; then
rm -rf -- "$application/Contents/Resources/Tools/LibreOffice.app"
if [[ "$twister_bundled_office" == false ]]; then
  print "LibreOffice is not bundled in this build."
elif [[ -d Tools/LibreOffice.app ]]; then
  twister_verify_developer_id Tools/LibreOffice.app "$twister_libreoffice_team" || exit 1
  twister_verify_libreoffice_version Tools/LibreOffice.app || exit 1
  ditto Tools/LibreOffice.app "$application/Contents/Resources/Tools/LibreOffice.app"
  twister_verify_developer_id "$application/Contents/Resources/Tools/LibreOffice.app" "$twister_libreoffice_team" || exit 1
  twister_verify_libreoffice_version "$application/Contents/Resources/Tools/LibreOffice.app" || exit 1
else
  print -u2 "Missing Tools/LibreOffice.app; see scripts/setup-tools.sh"
  exit 1
fi
fi
ditto Resources/Sounds "$application/Contents/Resources/Sounds"
cp Resources/PagesInterop.js "$application/Contents/Resources/PagesInterop.js"
cp Resources/PDFLib.js Resources/PDFInterop.js "$application/Contents/Resources/"
if [[ -f Resources/TwisterIcon.icns ]]; then cp Resources/TwisterIcon.icns "$application/Contents/Resources/TwisterIcon.icns"; fi
cp Resources/THIRD-PARTY-NOTICES.txt "$application/Contents/Resources/THIRD-PARTY-NOTICES.txt"
ditto Resources/licenses "$application/Contents/Resources/licenses"
sparkle_embedded="$application/Contents/Frameworks/Sparkle.framework/Versions/B"
if [[ "$twister_updates" == true ]]; then
cp "$sparkle_root/LICENSE" "$application/Contents/Resources/licenses/Sparkle-LICENSE.txt"
# Sign inside out. The downloader's sandbox entitlements must be retained.
codesign "${twister_signing_flags[@]}" "$sparkle_embedded/XPCServices/Installer.xpc"
codesign "${twister_signing_flags[@]}" --preserve-metadata=entitlements "$sparkle_embedded/XPCServices/Downloader.xpc"
codesign "${twister_signing_flags[@]}" "$sparkle_embedded/Autoupdate"
codesign "${twister_signing_flags[@]}" "$sparkle_embedded/Updater.app"
codesign "${twister_signing_flags[@]}" "$application/Contents/Frameworks/Sparkle.framework"
else
# Nothing outside the system is loaded, so library validation stays on.
twister_app_entitlements=()
fi
if [[ "$twister_public_build" == false ]]; then
codesign "${twister_signing_flags[@]}" "$application/Contents/Resources/Tools/ffmpeg"
codesign "${twister_signing_flags[@]}" "$application/Contents/Resources/Tools/ffprobe"
if [[ "$twister_web_downloads" == true ]]; then
# yt-dlp unpacks its Python runtime, signed by another team, when it starts.
codesign "${twister_signing_flags[@]}" --entitlements Configuration/yt-dlp.entitlements "$application/Contents/Resources/Tools/yt-dlp"
# Deno keeps its upstream Developer ID signature, which already uses the
# hardened runtime with the JIT entitlements it needs.
twister_verify_developer_id "$application/Contents/Resources/Tools/deno" "$twister_deno_team" || exit 1
fi
fi
codesign "${twister_signing_flags[@]}" "${twister_app_entitlements[@]}" "$application"
codesign --verify --deep --strict "$application"
twister_verify_signing_identity "$application" || exit 1
twister_runtime_code=("$application")
if [[ "$twister_updates" == true ]]; then
  twister_runtime_code+=("$application/Contents/Frameworks/Sparkle.framework" "$sparkle_embedded/Autoupdate" "$sparkle_embedded/Updater.app"
    "$sparkle_embedded/XPCServices/Installer.xpc" "$sparkle_embedded/XPCServices/Downloader.xpc")
fi
for component in ffmpeg ffprobe yt-dlp deno; do
  if [[ -e "$application/Contents/Resources/Tools/$component" ]]; then twister_runtime_code+=("$application/Contents/Resources/Tools/$component"); fi
done
twister_require_hardened_runtime "${twister_runtime_code[@]}" || exit 1
print "$application"
