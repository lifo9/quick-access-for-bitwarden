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

# Check every dependency on the Bitwarden desktop app; add "--unlock" to also request Touch ID
# and decrypt the vault. Prints counts and settings, never secrets.
diagnose *arguments:
    swift run QuickAccessForBitwarden --diagnose {{arguments}}
