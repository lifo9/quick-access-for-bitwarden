import Foundation

public enum VaultItemKind: Sendable, Equatable {
    case login
    case secureNote
    case card
    case identity
    case sshKey
}

/// What a field means for the keyboard shortcuts; everything without a shortcut is `other`.
public enum VaultFieldRole: Sendable, Equatable {
    case username
    case password
    case oneTimeCode
    case website
    case cardNumber
    case note
    case other
}

/// What a field defined by Bitwarden holds, for the app to name it in the user's language.
public enum StandardFieldName: Hashable, Sendable, CaseIterable {
    case username
    case password
    case oneTimeCode
    case website
    case notes
    case cardNumber
    case cardSecurityCode
    case cardholderName
    case cardExpirationMonth
    case cardExpirationYear
    case cardBrand
    case identityEmail
    case identityUsername
    case identityPhone
    case identityTitle
    case identityFirstName
    case identityMiddleName
    case identityLastName
    case identityCompany
    case identityAddress1
    case identityAddress2
    case identityAddress3
    case identityCity
    case identityState
    case identityPostalCode
    case identityCountry
    case identitySocialSecurityNumber
    case identityPassportNumber
    case identityLicenseNumber
    case sshPublicKey
    case sshKeyFingerprint
    case sshPrivateKey
}

/// The name of a field: one of Bitwarden's, or the user's own for a custom field.
public enum VaultFieldName: Hashable, Sendable {
    case standard(StandardFieldName)
    /// A custom field, with the name the user gave it.
    case custom(String)
    /// A custom field without a name; the number is its place among the item's custom fields.
    case unnamedCustom(Int)
}

/// One copyable value of an item. The value itself stays encrypted until `VaultItem.revealValue`
/// is called, so that secrets are only in memory in the clear while they are being used.
public struct VaultField: Identifiable, Sendable, Equatable {
    /// Unique within its item.
    public let id: String
    public let name: VaultFieldName
    public let role: VaultFieldRole
    /// Whether the desktop app hides this value behind a "reveal" toggle.
    public let isConcealed: Bool
    let encryptedValue: EncryptedString
    let itemKey: SymmetricCryptoKey
}

public enum VaultError: Error, Equatable {
    case userKeyDoesNotMatchAccount
    case masterPasswordRepromptRequired
    case unsupportedItemType(Int)
    case missingOrganizationKey
}

public struct VaultItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: VaultItemKind
    public let name: String
    /// The username of a login, or the closest equivalent of the other kinds.
    public let subtitle: String
    public let websites: [String]
    public let isFavorite: Bool
    /// The item has "master password re-prompt" switched on in Bitwarden.
    public let requiresMasterPasswordReprompt: Bool
    public let fields: [VaultField]

    public func revealValue(of field: VaultField) throws -> String {
        // This app never sees the master password, so it cannot perform the re-prompt. It
        // releases only what the list shows anyway, who the login is for and where, and refuses
        // everything else rather than deciding which other values are harmless.
        let isShownInTheList = field.role == .username || field.role == .website
        guard !requiresMasterPasswordReprompt || isShownInTheList else {
            throw VaultError.masterPasswordRepromptRequired
        }
        return try SymmetricCipher.decryptString(field.encryptedValue, with: field.itemKey)
    }

    public func firstField(withRole role: VaultFieldRole) -> VaultField? {
        fields.first { $0.role == role }
    }

    /// The field Return copies: the main secret of the item.
    public var defaultField: VaultField? {
        firstField(withRole: .password)
            ?? firstField(withRole: .cardNumber)
            ?? (kind == .secureNote ? firstField(withRole: .note) : nil)
            ?? primaryField
    }

    /// The field Command-C copies: the username, or what identifies the other kinds.
    public var primaryField: VaultField? {
        firstField(withRole: .username)
            ?? firstField(withRole: .cardNumber)
            ?? firstField(withRole: .note)
            ?? fields.first
    }
}

/// The decrypted, searchable vault of one account.
public struct UnlockedVault: Sendable {
    public let items: [VaultItem]
    /// Items that could not be decrypted, for example because they use an unsupported format.
    public let numUndecryptableItems: Int
}
