#!/bin/bash
# Builds a release: the app, signed with the Developer ID certificate and notarized, packed into a
# disk image that is signed and notarized as well. Prints the disk image's path as its last line.
#
# Run by the release workflow. Everything secret comes from the environment:
#   APPLE_KEY_ID, APPLE_ISSUER_ID   the App Store Connect API key used for notarization
#   APPLE_KEY_CONTENT               that key's .p8 file, Base64 encoded
#   MATCH_GIT_URL                   the fastlane match repository that holds the certificate
#   MATCH_GIT_BASIC_AUTHORIZATION   "user:token" with read access to that repository
#   MATCH_PASSWORD                  the passphrase that repository is encrypted with
#   TEMP_KEYCHAIN_PASSWORD          a password for the keychain made for this run
set -euo pipefail

for variable_name in APPLE_KEY_ID APPLE_ISSUER_ID APPLE_KEY_CONTENT MATCH_GIT_URL \
    MATCH_GIT_BASIC_AUTHORIZATION MATCH_PASSWORD TEMP_KEYCHAIN_PASSWORD; do
    if [ -z "${!variable_name:-}" ]; then
        echo "error: $variable_name is not set" >&2
        exit 1
    fi
done

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_identifier="dev.filo.quick-access-for-bitwarden"
app_bundle="$repo_root/build/Quick Access for Bitwarden.app"
keychain_name="quick-access-release.keychain"
keychain_file="$HOME/Library/Keychains/$keychain_name-db"
work_directory="$(mktemp -d)"
api_key_file="$work_directory/AuthKey.p8"

# The certificate and the API key exist on this machine only for the length of the run.
clean_up() {
    security delete-keychain "$keychain_file" 2>/dev/null || true
    rm -rf "$work_directory"
}
trap clean_up EXIT

echo "==> Creating a keychain for this run"
security delete-keychain "$keychain_file" 2>/dev/null || true
security create-keychain -p "$TEMP_KEYCHAIN_PASSWORD" "$keychain_file"
security set-keychain-settings -u -t 3600 "$keychain_file"
security unlock-keychain -p "$TEMP_KEYCHAIN_PASSWORD" "$keychain_file"
# codesign only finds identities in keychains that are on the search list.
existing_keychains=()
while IFS= read -r existing_keychain; do
    existing_keychains+=("$existing_keychain")
done < <(security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//')
security list-keychains -d user -s "$keychain_file" "${existing_keychains[@]}"

echo "==> Fetching the Developer ID certificate"
# fastlane match is used for this one step: the certificate is stored in its repository format.
# Read-only, so a release never creates or changes a certificate, and without provisioning
# profiles, which an app with no restricted capability does not need. match takes the repository
# credentials as an authorization header, hence the encoding.
(
    cd "$repo_root"
    MATCH_TYPE=developer_id \
        MATCH_PLATFORM=macos \
        MATCH_READONLY=true \
        MATCH_SKIP_PROVISIONING_PROFILES=true \
        MATCH_APP_IDENTIFIER="$app_identifier" \
        MATCH_KEYCHAIN_NAME="$keychain_name" \
        MATCH_KEYCHAIN_PASSWORD="$TEMP_KEYCHAIN_PASSWORD" \
        MATCH_GIT_BASIC_AUTHORIZATION="$(printf '%s' "$MATCH_GIT_BASIC_AUTHORIZATION" | base64 | tr -d '\n')" \
        FASTLANE_OPT_OUT_USAGE=YES \
        FASTLANE_SKIP_UPDATE_CHECK=1 \
        bundle exec fastlane match
)
if ! security find-identity -v -p codesigning "$keychain_file" | grep -q "Developer ID Application"; then
    echo "error: the match repository holds no Developer ID Application certificate;" \
        "see docs/releasing.md for how it is created" >&2
    exit 1
fi

(umask 077 && printf '%s' "$APPLE_KEY_CONTENT" | base64 --decode >"$api_key_file")

# Waits for Apple's verdict and fails unless it is "Accepted": the exit status of notarytool
# alone does not tell a rejected submission from an accepted one.
notarize() {
    local submission_file="$1"
    local submission
    submission="$(xcrun notarytool submit "$submission_file" --key "$api_key_file" \
        --key-id "$APPLE_KEY_ID" --issuer "$APPLE_ISSUER_ID" --wait --output-format json)"
    local submission_status
    submission_status="$(jq -r '.status' <<<"$submission")"
    if [ "$submission_status" != "Accepted" ]; then
        echo "error: notarization of $(basename "$submission_file") ended as '$submission_status'" >&2
        xcrun notarytool log "$(jq -r '.id' <<<"$submission")" --key "$api_key_file" \
            --key-id "$APPLE_KEY_ID" --issuer "$APPLE_ISSUER_ID" >&2 || true
        exit 1
    fi
}

export CODE_SIGN_IDENTITY="Developer ID Application"
export CODE_SIGN_KEYCHAIN="$keychain_file"

echo "==> Building and signing the app"
"$repo_root/scripts/bundle-app.sh"

echo "==> Notarizing the app"
# The app is notarized and stapled before it goes into the disk image, so that a copy dragged out
# of the image passes Gatekeeper without asking Apple. notarytool takes an archive, not a bundle.
ditto -c -k --keepParent "$app_bundle" "$work_directory/app.zip"
notarize "$work_directory/app.zip"
xcrun stapler staple "$app_bundle"

echo "==> Packing, signing and notarizing the disk image"
disk_image="$("$repo_root/scripts/make-disk-image.sh" | tail -n 1)"
notarize "$disk_image"
xcrun stapler staple "$disk_image"
xcrun stapler validate "$disk_image"

echo "$disk_image"
