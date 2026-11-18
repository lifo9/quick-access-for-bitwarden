#!/bin/bash
# Packs "build/Quick Access for Bitwarden.app" into a disk image named after the app's version,
# with a link to /Applications to drag the app onto, and prints the image's path.
#
# CODE_SIGN_IDENTITY and CODE_SIGN_KEYCHAIN are as in bundle-app.sh; the image is signed with the
# same identity as the app.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_bundle="$repo_root/build/Quick Access for Bitwarden.app"
code_sign_identity="${CODE_SIGN_IDENTITY:--}"
app_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app_bundle/Contents/Info.plist")"
disk_image="$repo_root/build/Quick-Access-for-Bitwarden-$app_version.dmg"

staging_directory="$(mktemp -d)"
trap 'rm -rf "$staging_directory"' EXIT
cp -R "$app_bundle" "$staging_directory/"
ln -s /Applications "$staging_directory/Applications"

rm -f "$disk_image"
hdiutil create -quiet -volname "Quick Access for Bitwarden" -srcfolder "$staging_directory" \
    -format UDZO "$disk_image"

code_sign_options=(--force --sign "$code_sign_identity")
if [ "$code_sign_identity" != "-" ]; then
    code_sign_options+=(--timestamp)
fi
if [ -n "${CODE_SIGN_KEYCHAIN:-}" ]; then
    code_sign_options+=(--keychain "$CODE_SIGN_KEYCHAIN")
fi
codesign "${code_sign_options[@]}" "$disk_image"

echo "$disk_image"
