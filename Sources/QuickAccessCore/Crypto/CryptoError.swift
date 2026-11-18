import Foundation

public enum CryptoError: Error, Equatable {
    case malformedEncryptedString
    case unsupportedEncryptionType(String)
    case unsupportedKeyLength(Int)
    case authenticationFailed
    case cipherOperationFailed(status: Int32)
    case plaintextIsNotUtf8
    case malformedPrivateKey
    case rsaOperationFailed(String)
    case randomGenerationFailed(status: Int32)
}
