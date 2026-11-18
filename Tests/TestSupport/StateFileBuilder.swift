import Foundation
import QuickAccessCore

/// Builds state files like the Bitwarden desktop app writes, for an account whose user key is
/// `Fixtures.userKey` and that belongs to one organization with `Fixtures.organizationKey`.
public enum StateFileBuilder {
    public static let userId = "11111111-2222-3333-4444-555555555555"
    public static let organizationId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    /// The Base32 secret of the RFC 6238 test vectors, used as the authenticator key of logins.
    public static let authenticatorKey = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

    /// - Parameters:
    ///   - ciphers: Vault items in the desktop app's JSON form, each with an `id`.
    ///   - settings: Further entries of the state file, keyed by their full state key.
    public static func makeStateFile(
        ciphers: [[String: Any]],
        settings: [String: Any] = [:],
        userId: String = userId
    ) throws -> Data {
        let ciphersById = Dictionary(uniqueKeysWithValues: ciphers.map { ($0["id"] as! String, $0) })
        let accountState: [String: Any] = [
            "global_account_activeAccountId": userId,
            "user_\(userId)_crypto_accountCryptographicState": [
                "V1": ["private_key": Fixtures.encrypt(Fixtures.pkcs8PrivateKey, with: Fixtures.userKey)]
            ],
            "user_\(userId)_crypto_organizationKeys": [
                organizationId: [
                    "type": "organization",
                    "key": "4." + Fixtures.wrappedOrganizationKey.base64EncodedString(),
                ]
            ],
            "user_\(userId)_ciphers_ciphers": ciphersById,
        ]
        let stateFile = accountState.merging(settings) { _, setting in setting }
        return try JSONSerialization.data(withJSONObject: stateFile)
    }

    /// The state key of a setting of the given account, as the desktop app names it.
    public static func settingKey(_ name: String, userId: String = userId) -> String {
        "user_\(userId)_\(name)"
    }

    /// A login with username `alice@example.com`, password `correct horse`, an authenticator key
    /// and one website.
    /// - Parameters:
    ///   - key: The key the values are encrypted with: the user key, or the item's own key.
    ///   - extra: Properties to add or replace in the item's JSON.
    public static func makeLogin(
        id: String = "login-1",
        name: String = "Example",
        username: String = "alice@example.com",
        key: SymmetricCryptoKey = Fixtures.userKey,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        let login: [String: Any] = [
            "username": Fixtures.encrypt(username, with: key),
            "password": Fixtures.encrypt("correct horse", with: key),
            "totp": Fixtures.encrypt(authenticatorKey, with: key),
            "uris": [["uri": Fixtures.encrypt("https://example.com/login", with: key), "match": NSNull()]],
        ]
        let cipher: [String: Any] = [
            "id": id,
            "type": 1,
            "name": Fixtures.encrypt(name, with: key),
            "notes": NSNull(),
            "favorite": false,
            "reprompt": 0,
            "viewPassword": true,
            "deletedDate": NSNull(),
            "login": login,
        ]
        return cipher.merging(extra) { _, override in override }
    }
}
