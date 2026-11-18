#!/bin/bash
# Builds the release binary and assembles "build/Bitwarden Quick Access.app".
#
# CODE_SIGN_IDENTITY selects the signing identity; the default "-" signs ad hoc, which is enough
# to run the app on the Mac that built it.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_bundle="$repo_root/build/Bitwarden Quick Access.app"
executable_name="BitwardenQuickAccess"

swift build --package-path "$repo_root" --configuration release
binaries_directory="$(swift build --package-path "$repo_root" --configuration release --show-bin-path)"

rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS"
cp "$binaries_directory/$executable_name" "$app_bundle/Contents/MacOS/$executable_name"
cp "$repo_root/Bundle/Info.plist" "$app_bundle/Contents/Info.plist"

codesign --force --options runtime --sign "${CODE_SIGN_IDENTITY:--}" "$app_bundle"
codesign --verify --strict "$app_bundle"

echo "Built $app_bundle"
