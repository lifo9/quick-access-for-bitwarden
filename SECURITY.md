# Security

This app handles the contents of a password vault, so reports of security problems are welcome
and are handled before anything else.

## Reporting a vulnerability

Report it privately through **Security → Report a vulnerability** on this repository (GitHub's
private vulnerability reporting). Do not open a public issue for it.

Include what you observed, the version of the app, of macOS and of the Bitwarden desktop app, and
the steps to reproduce it if you have them. Never include real vault contents, keys or tokens.

## Scope

In scope is this app: how it requests the unlock, reads and decrypts the desktop app's data,
keeps and forgets keys and values, uses the clipboard and fetches icons.

Problems in Bitwarden itself, its desktop app or its servers belong to Bitwarden:
<https://bitwarden.com/contact/>.

## Supported versions

Only the latest release receives fixes.

## Verifying a download

Releases are signed with a Developer ID certificate and notarized by Apple, which macOS checks
when the app is opened. The disk image of a release also carries a build provenance attestation:

```sh
gh attestation verify Quick-Access-for-Bitwarden-X.Y.Z.dmg --repo lifo9/quick-access-for-bitwarden
```
