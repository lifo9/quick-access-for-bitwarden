# Integration with the Bitwarden desktop app

The app depends on two internal interfaces of the Bitwarden desktop app. Neither is documented or
stable, so this file records what is relied on and where it lives upstream
([bitwarden/clients](https://github.com/bitwarden/clients)), to make adapting to a desktop app
update quick. Verified against Bitwarden desktop 2026.10.4.

## State file

`~/Library/Application Support/Bitwarden/data.json` (Mac App Store build:
`~/Library/Containers/com.bitwarden.desktop/Data/Library/Application Support/Bitwarden/data.json`).

A flat JSON object. Keys are `global_<group>_<name>` and `user_<user id>_<group>_<name>`.
`DesktopState` reads:

| Key                                               | Content                                                     |
| ------------------------------------------------- | ----------------------------------------------------------- |
| `global_account_activeAccountId`                  | User id of the account active in the desktop app            |
| `user_<id>_ciphers_ciphers`                       | Vault items by id, text values as encrypted strings         |
| `user_<id>_crypto_accountCryptographicState`      | `{"V1": {"private_key": …}}`, the encrypted RSA private key |
| `user_<id>_crypto_organizationKeys`               | Organization keys by organization id, RSA-wrapped           |
| `user_<id>_vaultTimeoutSettings_vaultTimeout`     | `never`, `onRestart`, `onLocked`, `onSleep`, `onIdle` or a number of minutes |
| `user_<id>_autofillSettingsLocal_clearClipboardDelay` | `never`, `tenSeconds`, … `fiveMinutes`                  |
| `user_<id>_biometricSettings_biometricUnlockEnabled`  | Whether Touch ID unlock is on                           |
| `global_domainSettings_showFavicons`              | "Show website icons"; on when absent                        |
| `global_translation_locale`                       | The desktop app's language, such as `sk`; absent when it follows the system |
| `user_<id>_environment_environment`               | `{"region", "urls": {"base", "icons", "webVault", …}}`, the account's server |

Values that are absent take the desktop app's defaults, which upstream defines in:

- vault timeout `onRestart`: `apps/desktop/src/app/services/services.module.ts`
  (`DEFAULT_VAULT_TIMEOUT`); the names in
  `libs/common/src/key-management/vault-timeout/types/vault-timeout.type.ts`
- clear clipboard `fiveMinutes`: `libs/common/src/autofill/services/autofill-settings.service.ts`;
  the names in `libs/common/src/autofill/constants/index.ts`
- "idle" means five minutes without input: `apps/desktop/src/main/power-monitor.main.ts`

### Website icons

The icon of a login is `<icon service>/<host name of its first website>/icon.png`
(`libs/common/src/vault/icon/build-cipher-icon.ts`). The icon service is `urls.icons` if set, else
`/icons` on `urls.base` or `urls.webVault`, else the service of the cloud region `US` or `EU`
(`libs/common/src/platform/services/default-environment.service.ts`). Where the desktop app would
fall back to the US cloud for an environment that names no server, this app shows no icons.

### Encryption

Encrypted strings are `<type>.<base64 parts joined by |>`. Supported: type 2 (AES-256-CBC with
HMAC-SHA256, `iv|ciphertext|mac`) and types 3 and 4 (RSA-2048-OAEP with SHA-256 and SHA-1). Every
other type, and an account state other than `V1`, is rejected.

Key hierarchy: the user key (64 bytes: AES key, then HMAC key) decrypts the private key (PKCS#8)
and personal items; the private key unwraps organization keys; an item with a `key` of its own has
that key wrapped by the user key or its organization's key.

## Biometric unlock over IPC

The desktop app serves its browser extension through a local socket. `desktop_proxy`, inside the
app bundle, relays native messaging frames (32 bit length in native byte order, then JSON) between
its standard input and output and that socket. This app spawns the proxy and speaks the
extension's protocol:

1. The proxy sends `{"command": "connected"}` once it has reached the desktop app.
2. Client: `{"appId", "message": {"command": "setupEncryption", "publicKey", "userId",
   "messageId", "timestamp"}}`, the public key being RSA-2048 SubjectPublicKeyInfo in Base64.
3. Desktop app: `{"appId", "command": "setupEncryption", "sharedSecret"}`, a 64 byte session key
   encrypted with RSA-OAEP-SHA1. `{"command": "wrongUserId"}` if the account is not logged in.
4. Every later message is JSON encrypted with the session key as a type 2 encrypted string:
   `{"appId", "message": {"encryptedString", "encryptionType", "data", "iv", "mac"}}`. Requests are
   `getBiometricsStatusForUser` and `unlockWithBiometricsForUser`; replies carry `messageId`,
   `timestamp`, `response` and, for a successful unlock, `userKeyB64`.

Both sides drop messages whose `timestamp` is more than ten seconds off. The desktop app
broadcasts to all connected clients, which tell their messages apart by `appId`.

Upstream sources:

- proxy: `apps/desktop/desktop_native/proxy/src/main.rs`
- desktop side: `apps/desktop/src/main/native-messaging.main.ts`,
  `apps/desktop/src/services/biometric-message-handler.service.ts`
- extension side, the model for this client: `apps/browser/src/background/nativeMessaging.background.ts`
- status values: `libs/key-management/src/biometrics/biometrics-status.ts`
- the Touch ID prompt: `apps/desktop/src/key-management/biometrics/os-biometrics-mac.service.ts`

The Touch ID prompt is a system dialog owned by the desktop app. No reply comes until the user
acts on it, and macOS fails it at once while the screen is locked.

The socket is in the desktop app's app group container
(`~/Library/Group Containers/LTZ2PFU5D6.com.bitwarden.desktop/s.bw`, see
`apps/desktop/desktop_native/core/src/ipc/mod.rs`). Only a process that is not sandboxed, or the
desktop app's own proxy, can reach it, which is why this app cannot be sandboxed and so cannot be
distributed through the Mac App Store. The proxy is expected at `Contents/MacOS/desktop_proxy` in
the desktop app's bundle; `InstalledDesktopApp.locateProxyExecutable` has to follow if upstream
moves it.

### Successor protocol

Upstream is moving this exchange to an IPC implemented in its Rust SDK, gated by the
`biometrics-sdk-ipc` feature flag (see `apps/cli/src/key-management/cli-biometrics-service.ts`).
When the protocol above is removed, `DesktopBiometricsClient` has to follow.

## When it stops working

- `just diagnose` reads the state file and asks the desktop app for the biometrics status, with no
  Touch ID prompt. `just diagnose --unlock` also requests an unlock and decrypts the vault. Both
  print counts and settings only.
- The desktop app logs its side to `~/Library/Application Support/Bitwarden/app.log`; the lines
  containing `Native messaging` and `Biometric` show whether a request arrived and how it ended.
