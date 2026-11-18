#!/bin/bash
# Builds the release binary and assembles "build/Quick Access for Bitwarden.app".
#
# CODE_SIGN_IDENTITY selects the signing identity; the default "-" signs ad hoc, which is enough
# to run the app on the Mac that built it. CODE_SIGN_KEYCHAIN names the keychain file to take the
# identity from, for a release build that keeps its certificate in a keychain of its own.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_bundle="$repo_root/build/Quick Access for Bitwarden.app"
executable_name="QuickAccessForBitwarden"
code_sign_identity="${CODE_SIGN_IDENTITY:--}"

swift build --package-path "$repo_root" --configuration release --product "$executable_name"
binaries_directory="$(swift build --package-path "$repo_root" --configuration release --show-bin-path)"

rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS"
cp "$binaries_directory/$executable_name" "$app_bundle/Contents/MacOS/$executable_name"
cp "$repo_root/Bundle/Info.plist" "$app_bundle/Contents/Info.plist"

code_sign_options=(--force --options runtime --sign "$code_sign_identity")
if [ "$code_sign_identity" != "-" ]; then
    # Notarization rejects a signature without a secure timestamp.
    code_sign_options+=(--timestamp)
fi
if [ -n "${CODE_SIGN_KEYCHAIN:-}" ]; then
    code_sign_options+=(--keychain "$CODE_SIGN_KEYCHAIN")
fi
codesign "${code_sign_options[@]}" "$app_bundle"
codesign --verify --strict "$app_bundle"

echo "Built $app_bundle"
