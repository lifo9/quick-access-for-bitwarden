import Foundation

public enum DesktopStateError: Error, Equatable {
    case noActiveAccount
    case missingAccountState(String)
    /// The account uses an encryption scheme newer than the classic one this app implements.
    case unsupportedAccountEncryption
}

/// What this app reads from the Bitwarden desktop app's state file (`data.json`) for the account
/// that is active there: the encrypted vault, the encrypted keys and the settings to follow.
///
/// The file is an internal format of the desktop app, a flat JSON object keyed by
/// `global_<group>_<name>` and `user_<user id>_<group>_<name>`.
public struct DesktopState: Sendable {
    public let userId: String
    public let encryptedPrivateKey: String
    public let organizationKeysByOrganizationId: [String: EncryptedOrganizationKey]
    public let ciphers: [EncryptedCipher]
    public let settings: DesktopSettings

    public init(
        userId: String,
        encryptedPrivateKey: String,
        organizationKeysByOrganizationId: [String: EncryptedOrganizationKey],
        ciphers: [EncryptedCipher],
        settings: DesktopSettings
    ) {
        self.userId = userId
        self.encryptedPrivateKey = encryptedPrivateKey
        self.organizationKeysByOrganizationId = organizationKeysByOrganizationId
        self.ciphers = ciphers
        self.settings = settings
    }

    public init(stateFileContents: Data) throws {
        self = try JSONDecoder().decode(StateFile.self, from: stateFileContents).desktopState
    }
}

private struct StateFile: Decodable {
    let desktopState: DesktopState

    private struct StateKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init(_ stringValue: String) {
            self.stringValue = stringValue
        }

        init?(stringValue: String) {
            self.init(stringValue)
        }

        init?(intValue: Int) {
            nil
        }
    }

    /// Classic account keys are stored as `{"V1": {"private_key": "<encrypted>"}}`. Newer schemes
    /// use other variant names, which leaves `v1` empty.
    private struct AccountCryptographicState: Decodable {
        struct ClassicKeys: Decodable {
            let privateKey: String

            enum CodingKeys: String, CodingKey {
                case privateKey = "private_key"
            }
        }

        let v1: ClassicKeys?

        enum CodingKeys: String, CodingKey {
            case v1 = "V1"
        }
    }

    /// The vault timeout is stored as a name ("onIdle") or as a number of minutes.
    private struct StoredVaultTimeout: Decodable {
        let vaultTimeout: VaultTimeout

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let minutes = try? container.decode(Int.self) {
                vaultTimeout = VaultTimeout(storedText: String(minutes))
            } else {
                vaultTimeout = VaultTimeout(storedText: try container.decode(String.self))
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StateKey.self)
        guard
            let userId = try container.decodeIfPresent(String.self, forKey: StateKey("global_account_activeAccountId"))
        else {
            throw DesktopStateError.noActiveAccount
        }

        func userStateKey(_ name: String) -> StateKey {
            StateKey("user_\(userId)_\(name)")
        }

        func decodeRequired<Stored: Decodable>(_ type: Stored.Type, _ name: String) throws -> Stored {
            guard let stored = try container.decodeIfPresent(type, forKey: userStateKey(name)) else {
                throw DesktopStateError.missingAccountState(name)
            }
            return stored
        }

        let cryptographicState = try decodeRequired(AccountCryptographicState.self, "crypto_accountCryptographicState")
        guard let classicKeys = cryptographicState.v1 else {
            throw DesktopStateError.unsupportedAccountEncryption
        }
        let ciphersById = try decodeRequired([String: EncryptedCipher].self, "ciphers_ciphers")
        let organizationKeysByOrganizationId =
            try container.decodeIfPresent(
                [String: EncryptedOrganizationKey].self,
                forKey: userStateKey("crypto_organizationKeys")
            ) ?? [:]

        let storedVaultTimeout = try container.decodeIfPresent(
            StoredVaultTimeout.self,
            forKey: userStateKey("vaultTimeoutSettings_vaultTimeout")
        )
        let storedClipboardClearDelay = try container.decodeIfPresent(
            String.self,
            forKey: userStateKey("autofillSettingsLocal_clearClipboardDelay")
        )
        let isBiometricUnlockEnabled =
            try container.decodeIfPresent(
                Bool.self,
                forKey: userStateKey("biometricSettings_biometricUnlockEnabled")
            ) ?? false

        // Icons are an extra: an environment in a shape this app does not know means no icons,
        // not a vault that cannot be read.
        let showsWebsiteIcons =
            (try? container.decodeIfPresent(Bool.self, forKey: StateKey("global_domainSettings_showFavicons")))
            ?? true
        let accountEnvironment = try? container.decodeIfPresent(
            StoredEnvironment.self,
            forKey: userStateKey("environment_environment")
        )
        let websiteIconServerUrl =
            showsWebsiteIcons ? WebsiteIcon.resolveIconServerUrl(environment: accountEnvironment) : nil

        desktopState = DesktopState(
            userId: userId,
            encryptedPrivateKey: classicKeys.privateKey,
            organizationKeysByOrganizationId: organizationKeysByOrganizationId,
            ciphers: Array(ciphersById.values),
            settings: DesktopSettings(
                vaultTimeout: storedVaultTimeout?.vaultTimeout ?? VaultTimeout.desktopDefault,
                clipboardClearDelay: storedClipboardClearDelay.map(ClipboardClearDelay.init(storedText:))
                    ?? ClipboardClearDelay.desktopDefault,
                isBiometricUnlockEnabled: isBiometricUnlockEnabled,
                websiteIconServerUrl: websiteIconServerUrl
            )
        )
    }
}
