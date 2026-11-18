default:
    @just --list

# The gate before a commit: format and lint check, build everything, run all tests.
check:
    swift format lint --strict --recursive Sources Tests Package.swift
    swift build --build-tests
    swift test

# Rewrite the sources in the format the check expects.
format:
    swift format --in-place --recursive Sources Tests Package.swift

# Assemble and sign "build/Quick Access for Bitwarden.app" from a release build.
bundle:
    scripts/bundle-app.sh

# Replace the copy in /Applications with a fresh build and start it.
install: bundle
    #!/usr/bin/env bash
    set -euo pipefail
    installed_app="/Applications/Quick Access for Bitwarden.app"
    pkill -x QuickAccessForBitwarden || true
    rm -rf "$installed_app"
    cp -R "build/Quick Access for Bitwarden.app" "$installed_app"
    open "$installed_app"

# Run the app against an invented vault instead of the Bitwarden desktop app: no Touch ID, no
# real data.
demo:
    swift run QuickAccessForBitwarden --demo

# Regenerate the screencast of the README from the demo vault, in both appearances.
screencast:
    swift run QuickAccessForBitwarden --record-demo docs/screencast

# Check every dependency on the Bitwarden desktop app; add "--unlock" to also request Touch ID
# and decrypt the vault. Prints counts and settings, never secrets.
diagnose *arguments:
    swift run QuickAccessForBitwarden --diagnose {{arguments}}

# Tag a release; release.yml signs, notarizes and publishes the disk image.
release version:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! printf '%s' "{{version}}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo "error: expected semver MAJOR.MINOR.PATCH, got '{{version}}'" >&2
        exit 1
    fi
    tag="v{{version}}"
    if [ -n "$(git status --porcelain)" ]; then
        echo "error: working tree is dirty; commit or stash before releasing" >&2
        exit 1
    fi
    if git rev-parse --verify --quiet "refs/tags/${tag}" >/dev/null; then
        echo "error: tag ${tag} already exists" >&2
        exit 1
    fi
    # Edited in place rather than rewritten by a plist tool, which would drop the comments.
    perl -0pi -e 's#(<key>CFBundle(?:ShortVersionString|Version)</key>\s*<string>)[^<]*#${1}{{version}}#g' Bundle/Info.plist
    git add Bundle/Info.plist
    git commit -m "chore(release): ${tag}"
    git tag "${tag}"
    git push origin HEAD "${tag}"
