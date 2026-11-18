import Foundation

/// A vault item as the desktop app stores it: structure in the clear, every text value an
/// encrypted string. Values stay unparsed here so that one item in an unsupported format is
/// skipped during decryption instead of making the whole file unreadable.
public struct EncryptedCipher: Decodable, Sendable {
    public let id: String
    public let type: Int
    public let organizationId: String?
    public let key: String?
    public let name: String?
    public let notes: String?
    public let favorite: Bool?
    public let reprompt: Int?
    public let viewPassword: Bool?
    public let deletedDate: String?
    public let archivedDate: String?
    public let login: EncryptedLogin?
    public let card: EncryptedCard?
    /// Identity has many optional text properties that are all handled alike, so it is kept as a
    /// dictionary of property name to encrypted value.
    public let identity: [String: String?]?
    public let sshKey: EncryptedSshKey?
    public let fields: [EncryptedCustomField]?
}

public struct EncryptedLogin: Decodable, Sendable {
    public let username: String?
    public let password: String?
    public let totp: String?
    public let uris: [EncryptedLoginUri]?
}

public struct EncryptedLoginUri: Decodable, Sendable {
    public let uri: String?
}

public struct EncryptedCard: Decodable, Sendable {
    public let cardholderName: String?
    public let brand: String?
    public let number: String?
    public let expMonth: String?
    public let expYear: String?
    public let code: String?
}

public struct EncryptedSshKey: Decodable, Sendable {
    public let privateKey: String?
    public let publicKey: String?
    public let keyFingerprint: String?
}

public struct EncryptedCustomField: Decodable, Sendable {
    public let name: String?
    public let value: String?
    public let type: Int?
}

/// An organization's symmetric key, wrapped for the account's RSA key pair.
public struct EncryptedOrganizationKey: Decodable, Sendable {
    public let type: String
    public let key: String?
}
