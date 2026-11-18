default:
    @just --list

# The gate before a commit: build everything, run all tests.
check:
    swift build --build-tests
    swift test

# Assemble and sign "build/Bitwarden Quick Access.app" from a release build.
bundle:
    scripts/bundle-app.sh

# Replace the copy in /Applications with a fresh build and start it.
install: bundle
    #!/usr/bin/env bash
    set -euo pipefail
    installed_app="/Applications/Bitwarden Quick Access.app"
    pkill -x BitwardenQuickAccess || true
    rm -rf "$installed_app"
    cp -R "build/Bitwarden Quick Access.app" "$installed_app"
    open "$installed_app"

# Check every dependency on the Bitwarden desktop app; add "--unlock" to also request Touch ID
# and decrypt the vault. Prints counts and settings, never secrets.
diagnose *arguments:
    swift run BitwardenQuickAccess --diagnose {{arguments}}
