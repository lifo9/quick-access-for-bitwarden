import Foundation

/// A Bitwarden AES-256-CBC + HMAC-SHA256 key: 32 bytes for encryption followed by 32 bytes for
/// authentication. The user key, organization keys, item keys and the desktop IPC session secret
/// all have this form.
public struct SymmetricCryptoKey: Sendable, Equatable {
    public static let encodedByteCount = 64
    private static let halfByteCount = 32

    let encryptionKey: Data
    let authenticationKey: Data

    public init(encodedKey: Data) throws {
        guard encodedKey.count == Self.encodedByteCount else {
            throw CryptoError.unsupportedKeyLength(encodedKey.count)
        }
        encryptionKey = Data(encodedKey.prefix(Self.halfByteCount))
        authenticationKey = Data(encodedKey.suffix(Self.halfByteCount))
    }

    public init(base64Encoded: String) throws {
        guard let encodedKey = Data(base64Encoded: base64Encoded) else {
            throw CryptoError.unsupportedKeyLength(0)
        }
        try self.init(encodedKey: encodedKey)
    }

    public var encodedKey: Data {
        encryptionKey + authenticationKey
    }
}
