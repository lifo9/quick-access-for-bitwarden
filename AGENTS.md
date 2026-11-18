# Bitwarden Quick Access

A macOS menu bar app: a Spotlight-style panel to search the Bitwarden vault and copy values. It is
a companion to the Bitwarden desktop app, which unlocks (Touch ID) and holds the synced vault.
[README.md](README.md) describes the behavior, [docs/desktop-integration.md](docs/desktop-integration.md)
the two desktop app internals it depends on.

## Checks

`just check` (`swift build --build-tests`, then `swift test`). There is no CI yet; run it before
every commit. `just bundle` builds the `.app`.

## Layout

- `Sources/QuickAccessCore`: everything without UI, with no AppKit: crypto, reading the desktop
  state file, vault decryption, one-time codes, search ranking, lock policy, the IPC client.
- `Sources/BitwardenQuickAccess`: the app: hot key, panel, model, session, clipboard.
- `Tests/TestSupport`: test vectors and the state file builder, shared by both test targets.

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
