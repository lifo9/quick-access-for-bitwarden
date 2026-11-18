# Quick Access for Bitwarden

A macOS menu bar app: a Spotlight-style panel to search the Bitwarden vault and copy values. It is
a companion to the Bitwarden desktop app, which unlocks (Touch ID) and holds the synced vault.
[README.md](README.md) describes the behavior, [docs/desktop-integration.md](docs/desktop-integration.md)
the two desktop app internals it depends on.

## Checks

`just check`: a syntax check of the shell scripts, `swift format lint --strict` over `Sources`,
`Tests` and `Package.swift`, then
`swift build --build-tests`, then `swift test`. Run it before every commit. `just format` applies
the format, `just bundle` builds the `.app`.

CI (`.github/workflows/ci.yml`) runs the same commands, one step each, and then
`scripts/bundle-app.sh`, on GitHub's `xcode-27` runner. It selects the Xcode version used for
development; when that changes, change it in the workflow too, since the format check follows the
toolchain. A command added to `just check` has to be added to the workflow as well.

Changes reach `main` only through pull requests, squash-merged after `ci` has passed; Dependabot's
are merged automatically on that condition (`.github/workflows/dependabot-auto-merge.yml`, which
relies on the rule for `main` that requires the checks).

`just release X.Y.Z` opens the pull request that sets a new version; merging it makes
`.github/workflows/release.yml` sign, notarize and publish the disk image.
[docs/releasing.md](docs/releasing.md) has the steps and the one-time setup. `scripts/release.sh`
cannot run without the signing secrets; `scripts/bundle-app.sh && scripts/make-disk-image.sh`
exercises the packaging with an ad hoc signature.

## Layout

- `Sources/QuickAccessCore`: everything without UI, with no AppKit: crypto, reading the desktop
  state file, vault decryption, one-time codes, search ranking, lock policy, the IPC client.
- `Sources/QuickAccessForBitwarden`: the app: hot key, panel, model, session, clipboard, icons.
  `Demo/` holds an invented vault (`--demo`, `just demo`) and the recorder of the README's
  screencast (`just screencast`); rerun the recorder after a change to the panel's look.
- `Tests/TestSupport`: test vectors and the state file builder, shared by both test targets.
- `scripts/`: building the app bundle and the disk image, and the release that signs and
  notarizes them. `Gemfile` pins fastlane, which the release uses only to fetch the certificate.

## Rules

- **Never print, log or persist vault contents, keys or tokens.** Diagnostics print counts and
  settings only. When inspecting a real state file, print key names and shapes, not values.
- **Unknown formats fail closed.** An encryption type, account state or setting value the code
  does not know is rejected or read in the strictest way, never guessed.
- **Crypto uses Apple's frameworks only** (CommonCrypto, CryptoKit, Security); no dependencies.
- **Everything that reaches the desktop app goes through `DesktopAccess`.** Tests replace it with a
  fake and build state files with `StateFileBuilder`; they never read the real state file or
  talk to the real desktop app.
- **Crypto test vectors come from an independent implementation** (OpenSSL, Python `hmac`), not
  from this code's own output.
- The desktop app's settings are the configuration. Do not add a setting here for something the
  desktop app already has one for.

## Verifying against the real desktop app

`just diagnose` needs the desktop app running; `just diagnose --unlock` and the app itself show a
Touch ID prompt that only the person at the Mac can confirm. The prompt fails at once while the
screen is locked, which looks like "Touch ID was cancelled".
