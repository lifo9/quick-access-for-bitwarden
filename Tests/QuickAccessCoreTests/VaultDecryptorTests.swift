import Foundation
import QuickAccessTestSupport
import XCTest

@testable import QuickAccessCore

final class VaultDecryptorTests: XCTestCase {
    private let userId = StateFileBuilder.userId
    private let organizationId = StateFileBuilder.organizationId
    private let itemKey = try! SymmetricCryptoKey(encodedKey: Data(repeating: 9, count: 64))

    private func makeStateFile(ciphers: [[String: Any]], settings: [String: Any] = [:]) throws -> Data {
        try StateFileBuilder.makeStateFile(ciphers: ciphers, settings: settings)
    }

    private func unlock(ciphers: [[String: Any]]) throws -> UnlockedVault {
        let state = try DesktopState(stateFileContents: makeStateFile(ciphers: ciphers))
        return try VaultDecryptor.unlock(state, userKey: Fixtures.userKey)
    }

    private func makeLogin(
        id: String = "login-1",
        name: String = "Example",
        key: SymmetricCryptoKey = Fixtures.userKey,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        StateFileBuilder.makeLogin(id: id, name: name, key: key, extra: extra)
    }

    private func revealValue(ofFieldWithRole role: VaultFieldRole, in item: VaultItem) throws -> String {
        try item.revealValue(of: XCTUnwrap(item.firstField(withRole: role)))
    }

    func test_unlock__decryptsPersonalLogin() throws {
        let vault = try unlock(ciphers: [makeLogin()])

        let item = try XCTUnwrap(vault.items.first)
        XCTAssertEqual(vault.numUndecryptableItems, 0)
        XCTAssertEqual(item.kind, .login)
        XCTAssertEqual(item.name, "Example")
        XCTAssertEqual(item.subtitle, "alice@example.com")
        XCTAssertEqual(item.websites, ["https://example.com/login"])
        XCTAssertEqual(try revealValue(ofFieldWithRole: .username, in: item), "alice@example.com")
        XCTAssertEqual(try revealValue(ofFieldWithRole: .password, in: item), "correct horse")
        XCTAssertEqual(try revealValue(ofFieldWithRole: .oneTimeCode, in: item), "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
        XCTAssertEqual(item.defaultField?.role, .password)
        XCTAssertEqual(item.primaryField?.role, .username)
    }

    func test_unlock__decryptsOrganizationItemThatHasItsOwnKey() throws {
        let organizationItem = makeLogin(
            name: "Shared",
            key: itemKey,
            extra: [
                "organizationId": organizationId,
                "key": Fixtures.encrypt(itemKey.encodedKey, with: Fixtures.organizationKey),
            ]
        )

        let vault = try unlock(ciphers: [organizationItem])

        let item = try XCTUnwrap(vault.items.first)
        XCTAssertEqual(item.name, "Shared")
        XCTAssertEqual(try revealValue(ofFieldWithRole: .password, in: item), "correct horse")
    }

    func test_unlock__decryptsCardWithNumberAsDefaultField() throws {
        let card: [String: Any] = [
            "id": "card-1",
            "type": 3,
            "name": Fixtures.encrypt("Visa", with: Fixtures.userKey),
            "card": [
                "cardholderName": Fixtures.encrypt("Alice Example", with: Fixtures.userKey),
                "brand": Fixtures.encrypt("Visa", with: Fixtures.userKey),
                "number": Fixtures.encrypt("4111111111111111", with: Fixtures.userKey),
                "expMonth": Fixtures.encrypt("12", with: Fixtures.userKey),
                "expYear": Fixtures.encrypt("2030", with: Fixtures.userKey),
                "code": Fixtures.encrypt("123", with: Fixtures.userKey),
            ],
        ]

        let item = try XCTUnwrap(unlock(ciphers: [card]).items.first)

        XCTAssertEqual(item.kind, .card)
        XCTAssertEqual(item.subtitle, "Visa")
        XCTAssertEqual(try item.revealValue(of: XCTUnwrap(item.defaultField)), "4111111111111111")
        XCTAssertEqual(
            item.fields.map(\.label),
            ["Number", "Security code", "Cardholder name", "Expiration month", "Expiration year", "Brand"])
    }

    func test_unlock__decryptsSecureNoteAndCustomFields() throws {
        let note: [String: Any] = [
            "id": "note-1",
            "type": 2,
            "name": Fixtures.encrypt("Wi-Fi", with: Fixtures.userKey),
            "notes": Fixtures.encrypt("guest network", with: Fixtures.userKey),
            "secureNote": ["type": 0],
            "fields": [
                [
                    "name": Fixtures.encrypt("SSID", with: Fixtures.userKey),
                    "value": Fixtures.encrypt("home", with: Fixtures.userKey), "type": 0, "linkedId": NSNull(),
                ],
                [
                    "name": Fixtures.encrypt("Key", with: Fixtures.userKey),
                    "value": Fixtures.encrypt("hunter2", with: Fixtures.userKey), "type": 1, "linkedId": NSNull(),
                ],
                [
                    "name": Fixtures.encrypt("Linked", with: Fixtures.userKey), "value": NSNull(), "type": 3,
                    "linkedId": 100,
                ],
            ],
        ]

        let item = try XCTUnwrap(unlock(ciphers: [note]).items.first)

        XCTAssertEqual(item.kind, .secureNote)
        XCTAssertEqual(try item.revealValue(of: XCTUnwrap(item.defaultField)), "guest network")
        XCTAssertEqual(item.fields.map(\.label), ["Notes", "SSID", "Key"])
        XCTAssertEqual(item.fields.map(\.isConcealed), [false, false, true])
        XCTAssertEqual(try item.revealValue(of: item.fields[2]), "hunter2")
    }

    func test_unlock__decryptsIdentityWithNameAsSubtitle() throws {
        let identity: [String: Any] = [
            "id": "identity-1",
            "type": 4,
            "name": Fixtures.encrypt("Me", with: Fixtures.userKey),
            "identity": [
                "firstName": Fixtures.encrypt("Alice", with: Fixtures.userKey),
                "lastName": Fixtures.encrypt("Example", with: Fixtures.userKey),
                "email": Fixtures.encrypt("alice@example.com", with: Fixtures.userKey),
                "ssn": Fixtures.encrypt("123-45-6789", with: Fixtures.userKey),
                "phone": NSNull(),
            ],
        ]

        let item = try XCTUnwrap(unlock(ciphers: [identity]).items.first)

        XCTAssertEqual(item.subtitle, "Alice Example")
        XCTAssertEqual(item.fields.map(\.label), ["Email", "First name", "Last name", "Social security number"])
        XCTAssertEqual(item.fields.last?.isConcealed, true)
    }

    func test_unlock__skipsDeletedAndArchivedItems() throws {
        let vault = try unlock(ciphers: [
            makeLogin(id: "kept"),
            makeLogin(id: "deleted", extra: ["deletedDate": "2026-01-01T00:00:00Z"]),
            makeLogin(id: "archived", extra: ["archivedDate": "2026-01-01T00:00:00Z"]),
        ])

        XCTAssertEqual(vault.items.map(\.id), ["kept"])
        XCTAssertEqual(vault.numUndecryptableItems, 0)
    }

    func test_unlock__countsItemsItCannotDecryptAndKeepsTheRest() throws {
        let vault = try unlock(ciphers: [
            makeLogin(id: "readable"),
            makeLogin(id: "newer-format", extra: ["name": "7.AAAA"]),
            makeLogin(id: "foreign-key", key: itemKey),
            makeLogin(id: "unknown-organization", extra: ["organizationId": "ffffffff-0000-0000-0000-000000000000"]),
        ])

        XCTAssertEqual(vault.items.map(\.id), ["readable"])
        XCTAssertEqual(vault.numUndecryptableItems, 3)
    }

    func test_unlock__throwsWhenUserKeyBelongsToAnotherAccount() throws {
        let state = try DesktopState(stateFileContents: makeStateFile(ciphers: [makeLogin()]))

        XCTAssertThrowsError(try VaultDecryptor.unlock(state, userKey: itemKey)) { error in
            XCTAssertEqual(error as? VaultError, .userKeyDoesNotMatchAccount)
        }
    }

    func test_unlock__withholdsSecretsWithoutViewPasswordPermission() throws {
        let item = try XCTUnwrap(unlock(ciphers: [makeLogin(extra: ["viewPassword": false])]).items.first)

        XCTAssertNil(item.firstField(withRole: .password))
        XCTAssertNil(item.firstField(withRole: .oneTimeCode))
        XCTAssertEqual(try revealValue(ofFieldWithRole: .username, in: item), "alice@example.com")
    }

    func test_revealValue__refusesConcealedFieldsOfItemWithMasterPasswordReprompt() throws {
        let item = try XCTUnwrap(unlock(ciphers: [makeLogin(extra: ["reprompt": 1])]).items.first)

        XCTAssertThrowsError(try revealValue(ofFieldWithRole: .password, in: item)) { error in
            XCTAssertEqual(error as? VaultError, .masterPasswordRepromptRequired)
        }
        XCTAssertThrowsError(try revealValue(ofFieldWithRole: .oneTimeCode, in: item))
        XCTAssertEqual(try revealValue(ofFieldWithRole: .username, in: item), "alice@example.com")
    }

    // MARK: - Reading the state file

    func test_DesktopState_init__readsTheSettingsOfTheActiveAccount() throws {
        let state = try DesktopState(
            stateFileContents: makeStateFile(
                ciphers: [],
                settings: [
                    "user_\(userId)_vaultTimeoutSettings_vaultTimeout": "onIdle",
                    "user_\(userId)_autofillSettingsLocal_clearClipboardDelay": "thirtySeconds",
                    "user_\(userId)_biometricSettings_biometricUnlockEnabled": true,
                    "user_other-account_vaultTimeoutSettings_vaultTimeout": "never",
                ]))

        XCTAssertEqual(state.userId, userId)
        XCTAssertEqual(
            state.settings,
            DesktopSettings(
                vaultTimeout: .onSystemIdle,
                clipboardClearDelay: .seconds(30),
                isBiometricUnlockEnabled: true
            ))
    }

    func test_DesktopState_init__readsVaultTimeoutGivenInMinutes() throws {
        let state = try DesktopState(
            stateFileContents: makeStateFile(
                ciphers: [],
                settings: [
                    "user_\(userId)_vaultTimeoutSettings_vaultTimeout": 15
                ]))

        XCTAssertEqual(state.settings.vaultTimeout, .afterMinutes(15))
    }

    func test_DesktopState_init__appliesDesktopDefaultsWhenSettingsWereNeverChanged() throws {
        let state = try DesktopState(stateFileContents: makeStateFile(ciphers: []))

        XCTAssertEqual(
            state.settings,
            DesktopSettings(
                vaultTimeout: .onRestart,
                clipboardClearDelay: .seconds(300),
                isBiometricUnlockEnabled: false
            ))
    }

    func test_DesktopState_init__treatsUnknownSettingValuesStrictly() throws {
        let state = try DesktopState(
            stateFileContents: makeStateFile(
                ciphers: [],
                settings: [
                    "user_\(userId)_vaultTimeoutSettings_vaultTimeout": "onFullMoon",
                    "user_\(userId)_autofillSettingsLocal_clearClipboardDelay": "eventually",
                ]))

        XCTAssertEqual(state.settings.vaultTimeout, .unrecognized)
        XCTAssertEqual(state.settings.clipboardClearDelay, .seconds(30))
    }

    func test_DesktopState_init__throwsWhenNobodyIsLoggedIn() throws {
        let stateFile = try JSONSerialization.data(withJSONObject: ["global_account_activeAccountId": NSNull()])

        XCTAssertThrowsError(try DesktopState(stateFileContents: stateFile)) { error in
            XCTAssertEqual(error as? DesktopStateError, .noActiveAccount)
        }
    }

    func test_DesktopState_init__throwsForAccountWithNewerEncryptionScheme() throws {
        let stateFile = try JSONSerialization.data(withJSONObject: [
            "global_account_activeAccountId": userId,
            "user_\(userId)_crypto_accountCryptographicState": ["V2": ["private_key": "7.AAAA"]],
            "user_\(userId)_ciphers_ciphers": [String: Any](),
        ])

        XCTAssertThrowsError(try DesktopState(stateFileContents: stateFile)) { error in
            XCTAssertEqual(error as? DesktopStateError, .unsupportedAccountEncryption)
        }
    }
}
