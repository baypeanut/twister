#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration=${1:-release}
python3 scripts/setup-resources.py
source scripts/signing-configuration.sh
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
# SwiftPM also embeds a literal fallback resource path, which compiler prefix
# maps do not rewrite. Build in a private temporary directory outside the home
# folder, then prove the packaged app works after this directory is removed.
twister_build_directory=$(mktemp -d /tmp/twister-swift.XXXXXX)
trap 'rm -rf -- "$twister_build_directory"' EXIT
swift build --scratch-path "$twister_build_directory" -c "$configuration" --product Twister -Xswiftc -file-prefix-map -Xswiftc "$PWD=/twister" -Xswiftc -file-compilation-dir -Xswiftc /twister
binary_dir=$(swift build --scratch-path "$twister_build_directory" -c "$configuration" --show-bin-path)
application=${TWISTER_APP_OUTPUT:-"$PWD/build/Twister.app"}
sparkle_root="$twister_build_directory/artifacts/sparkle/Sparkle"
sparkle_framework="$sparkle_root/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$sparkle_framework" ]]; then print -u2 "Missing Sparkle framework; run swift package resolve"; exit 1; fi
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
cp Resources/Info.plist "$application/Contents/Info.plist"
python3 scripts/generate-localizations.py
ditto Resources/Localizations "$application/Contents/Resources"
if [[ -d "$binary_dir/Twister_TwisterCore.bundle" ]]; then ditto "$binary_dir/Twister_TwisterCore.bundle" "$application/Contents/Resources/Twister_TwisterCore.bundle"; fi
python3 scripts/configure-updates.py "$application/Contents/Info.plist" "${TWISTER_UPDATE_CONFIG:-Configuration/Updates.plist}"
if [[ "$twister_web_downloads" == false ]]; then
  plutil -replace TwisterWebDownloads -bool false "$application/Contents/Info.plist"
  rm -f -- "$application/Contents/Resources/Tools/yt-dlp" "$application/Contents/Resources/Tools/deno"
fi
mkdir -p "$application/Contents/Frameworks"
if [[ -d "$application/Contents/Frameworks/Sparkle.framework" ]]; then rm -rf "$application/Contents/Frameworks/Sparkle.framework"; fi
ditto "$sparkle_framework" "$application/Contents/Frameworks/Sparkle.framework"
if [[ "$twister_public_build" == true ]]; then
  if [[ -e "$application/Contents/Resources/Tools/ffmpeg" || -d "$application/Contents/Resources/Tools/LibreOffice.app" ]]; then
    print -u2 'Public packages require a fresh output directory without bundled third-party runtimes.'; exit 1
  fi
  plutil -replace TwisterExternalTools -bool true "$application/Contents/Info.plist"
else
for component in "${twister_bundled_tools[@]}"; do
  if [[ ! -x "Tools/$component" ]]; then print -u2 "Missing Tools/$component; see scripts/setup-tools.sh and scripts/setup-web-download-tools.py"; exit 1; fi
  cp "Tools/$component" "$application/Contents/Resources/Tools/$component"
done
fi
if [[ -f Tools/ExifTool/exiftool ]]; then
  ditto Tools/ExifTool "$application/Contents/Resources/Tools/ExifTool"
else
  print -u2 "Missing Tools/ExifTool; run scripts/setup-exiftool.sh"
  exit 1
fi
if [[ "$twister_public_build" == false ]]; then
if [[ -d Tools/LibreOffice.app ]]; then
  ditto Tools/LibreOffice.app "$application/Contents/Resources/Tools/LibreOffice.app"
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
cp "$sparkle_root/LICENSE" "$application/Contents/Resources/licenses/Sparkle-LICENSE.txt"
sparkle_embedded="$application/Contents/Frameworks/Sparkle.framework/Versions/B"
# Sign inside out. The downloader's sandbox entitlements must be retained.
codesign "${twister_signing_flags[@]}" "$sparkle_embedded/XPCServices/Installer.xpc"
codesign "${twister_signing_flags[@]}" --preserve-metadata=entitlements "$sparkle_embedded/XPCServices/Downloader.xpc"
codesign "${twister_signing_flags[@]}" "$sparkle_embedded/Autoupdate"
codesign "${twister_signing_flags[@]}" "$sparkle_embedded/Updater.app"
codesign "${twister_signing_flags[@]}" "$application/Contents/Frameworks/Sparkle.framework"
if [[ "$twister_public_build" == false ]]; then
codesign "${twister_signing_flags[@]}" "$application/Contents/Resources/Tools/ffmpeg"
codesign "${twister_signing_flags[@]}" "$application/Contents/Resources/Tools/ffprobe"
if [[ "$twister_web_downloads" == true ]]; then
codesign "${twister_signing_flags[@]}" "$application/Contents/Resources/Tools/yt-dlp"
codesign "${twister_signing_flags[@]}" --entitlements Configuration/Deno.entitlements "$application/Contents/Resources/Tools/deno"
fi
fi
codesign "${twister_signing_flags[@]}" "$application"
codesign --verify --deep --strict "$application"
twister_verify_signing_identity "$application"
print "$application"
