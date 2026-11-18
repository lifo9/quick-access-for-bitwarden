import Foundation

/// A value in Bitwarden's serialized "EncString" form: `<type>.<base64 parts separated by |>`.
///
/// Only the types found in accounts with the classic (V1) encryption are supported. Any other type
/// is rejected, so a vault migrated to a newer format fails loudly instead of being misread.
public enum EncryptedString: Sendable, Equatable {
    /// Type 2: `2.<iv>|<ciphertext>|<mac>`.
    case aesCbc256HmacSha256(initializationVector: Data, ciphertext: Data, authenticationCode: Data)
    /// Type 3: `3.<ciphertext>`.
    case rsa2048OaepSha256(ciphertext: Data)
    /// Type 4: `4.<ciphertext>`.
    case rsa2048OaepSha1(ciphertext: Data)

    public init(serialized: String) throws {
        let typeAndPayload = serialized.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard typeAndPayload.count == 2 else {
            throw CryptoError.malformedEncryptedString
        }
        let encryptionType = String(typeAndPayload[0])
        let parts = try typeAndPayload[1]
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { part -> Data in
                guard let decodedPart = Data(base64Encoded: String(part)), !decodedPart.isEmpty else {
                    throw CryptoError.malformedEncryptedString
                }
                return decodedPart
            }

        if encryptionType == "2", parts.count == 3 {
            self = .aesCbc256HmacSha256(
                initializationVector: parts[0],
                ciphertext: parts[1],
                authenticationCode: parts[2]
            )
        } else if encryptionType == "3", parts.count == 1 {
            self = .rsa2048OaepSha256(ciphertext: parts[0])
        } else if encryptionType == "4", parts.count == 1 {
            self = .rsa2048OaepSha1(ciphertext: parts[0])
        } else if ["2", "3", "4"].contains(encryptionType) {
            throw CryptoError.malformedEncryptedString
        } else {
            throw CryptoError.unsupportedEncryptionType(encryptionType)
        }
    }

    public var serialized: String {
        switch self {
        case .aesCbc256HmacSha256(let initializationVector, let ciphertext, let authenticationCode):
            let parts = [initializationVector, ciphertext, authenticationCode]
            return "2." + parts.map { $0.base64EncodedString() }.joined(separator: "|")
        case .rsa2048OaepSha256(let ciphertext):
            return "3." + ciphertext.base64EncodedString()
        case .rsa2048OaepSha1(let ciphertext):
            return "4." + ciphertext.base64EncodedString()
        }
    }
}
