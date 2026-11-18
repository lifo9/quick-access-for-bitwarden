# Quick Access for Bitwarden

A macOS menu bar app that opens a Spotlight-style panel on a global shortcut to search a Bitwarden
vault and copy usernames, passwords, one-time codes and other fields, without switching to the
Bitwarden app.

It is a companion to the official Bitwarden desktop app, not a Bitwarden client of its own. It is
not affiliated with Bitwarden.

## How it works

- **Unlock.** The app asks the running Bitwarden desktop app to unlock, over the local IPC the
  Bitwarden browser extension uses. The desktop app shows its own Touch ID prompt and hands over
  the vault key. The app never sees the master password and stores no key anywhere.
- **Vault.** Items come from the desktop app's local state file, which holds the account that is
  active in the desktop app, and are decrypted in memory with Apple's CommonCrypto, CryptoKit and
  Security frameworks. Secret values stay encrypted until the moment they are copied.
- **Settings.** The app follows the desktop app's settings instead of having its own:

  | Bitwarden desktop setting      | Effect here                                                      |
  | ------------------------------ | ---------------------------------------------------------------- |
  | Vault timeout                  | When the app forgets the vault key (idle, sleep, screen lock, …) |
  | Clear clipboard                | When a copied value is removed from the clipboard                |
  | Unlock with Touch ID           | Must be on; it is the only way to unlock                         |
  | Master password re-prompt      | Secret fields of such items are refused, not revealed            |
  | "View password" off (shared)   | Password and one-time code of the item are not offered           |

There is no network access, no login and no synchronization: what the desktop app has synced is
what the panel shows.

## Requirements

- macOS 15 or later (the deployment target; developed and tested on macOS 27).
- Xcode with Swift 6 or later to build (developed with Xcode 27.2).
- The Bitwarden desktop app, running and logged in, with **Unlock with Touch ID** switched on
  in its settings. Developed against version 2026.10.4.
- An account with Bitwarden's classic encryption (see Limitations).

## Build and install

```sh
just install    # builds, copies the app to /Applications and starts it
```

Without `just`: `scripts/bundle-app.sh` builds `build/Quick Access for Bitwarden.app`; copy it to
`/Applications` and open it. The app is signed ad hoc, which runs on the Mac that built it. Set
`CODE_SIGN_IDENTITY` to sign with a certificate instead.

"Launch at Login" is in the menu of the menu bar icon.

## Use

**⇧⌘Space** opens and closes the panel from any app.

| Key        | Action                                                      |
| ---------- | ----------------------------------------------------------- |
| ↑ ↓        | Move the selection                                          |
| ↩          | Copy the password (card number, note) and close             |
| ⌘C         | Copy the username, or the main field of other item kinds    |
| ⇧⌘C        | Copy the password                                           |
| ⌥⌘C        | Copy the current one-time code                              |
| ⌥↩         | Open the item's website in the browser                      |
| →          | Show everything that can be done with the selected item     |
| ←          | Back to the list                                            |
| Esc        | Back, then clear the search, then close                     |

Before anything is typed, the list suggests items named after the app in front, then the items
used most often, then favorites.

On macOS versions where the system uses ⇧⌘Space itself ("Ask Siri about active window"), switch
that shortcut off under System Settings → Keyboard → Keyboard Shortcuts.

## Limitations

- **Depends on internals of the Bitwarden desktop app.** Neither the state file nor the IPC is a
  public interface. A desktop app update can break unlocking or reading until this app is adapted;
  it then fails with a message rather than showing wrong data. `just diagnose` reports which part
  stopped working. See [docs/desktop-integration.md](docs/desktop-integration.md).
- **Classic encryption only.** Accounts or items in Bitwarden's newer encryption formats are
  refused: the app reports unsupported items instead of guessing.
- Only the account active in the desktop app. No attachments, passkeys, Sends, editing or autofill.

## Security notes

- The vault key and decrypted values live only in this process's memory and are dropped on lock
  and on quit. Nothing secret is written to disk; the preferences hold item ids with use counts
  and a random client id.
- Copied secrets carry the marker that tells clipboard managers not to record them, and are
  removed after the desktop app's clear-clipboard delay if they are still on the clipboard.
- The desktop app's IPC does not authenticate its clients: any process of the same user can ask
  for a Touch ID unlock. This app does not widen that; it is one more such client.

## Development

`just check` builds everything and runs the tests. See [AGENTS.md](AGENTS.md) for the layout.
