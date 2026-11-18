import CommonCrypto
import CryptoKit
import Foundation

/// AES-256-CBC with PKCS#7 padding, authenticated with HMAC-SHA256 over `iv || ciphertext`
/// (encrypt-then-MAC), as Bitwarden uses for type 2 encrypted strings.
public enum SymmetricCipher {
    public static let initializationVectorByteCount = kCCBlockSizeAES128

    public static func decrypt(_ encrypted: EncryptedString, with key: SymmetricCryptoKey) throws -> Data {
        guard case .aesCbc256HmacSha256(let initializationVector, let ciphertext, let authenticationCode) = encrypted
        else {
            throw CryptoError.unsupportedEncryptionType("asymmetric value given to the symmetric cipher")
        }
        // The MAC is checked before any decryption so that tampered input never reaches the cipher.
        let isAuthentic = HMAC<SHA256>.isValidAuthenticationCode(
            authenticationCode,
            authenticating: initializationVector + ciphertext,
            using: SymmetricKey(data: key.authenticationKey)
        )
        guard isAuthentic else {
            throw CryptoError.authenticationFailed
        }
        return try runAesCbc(
            operation: CCOperation(kCCDecrypt),
            input: ciphertext,
            encryptionKey: key.encryptionKey,
            initializationVector: initializationVector
        )
    }

    public static func decryptString(_ encrypted: EncryptedString, with key: SymmetricCryptoKey) throws -> String {
        let plaintext = try decrypt(encrypted, with: key)
        guard let text = String(data: plaintext, encoding: .utf8) else {
            throw CryptoError.plaintextIsNotUtf8
        }
        return text
    }

    /// The initialization vector is a parameter so the function stays deterministic; callers pass
    /// fresh random bytes from `RandomBytes.generate`.
    public static func encrypt(
        _ plaintext: Data,
        with key: SymmetricCryptoKey,
        initializationVector: Data
    ) throws -> EncryptedString {
        precondition(
            initializationVector.count == initializationVectorByteCount,
            "AES-CBC needs a 16 byte initialization vector"
        )
        let ciphertext = try runAesCbc(
            operation: CCOperation(kCCEncrypt),
            input: plaintext,
            encryptionKey: key.encryptionKey,
            initializationVector: initializationVector
        )
        let authenticationCode = HMAC<SHA256>.authenticationCode(
            for: initializationVector + ciphertext,
            using: SymmetricKey(data: key.authenticationKey)
        )
        return .aesCbc256HmacSha256(
            initializationVector: initializationVector,
            ciphertext: ciphertext,
            authenticationCode: Data(authenticationCode)
        )
    }

    private static func runAesCbc(
        operation: CCOperation,
        input: Data,
        encryptionKey: Data,
        initializationVector: Data
    ) throws -> Data {
        guard initializationVector.count == initializationVectorByteCount else {
            throw CryptoError.malformedEncryptedString
        }
        // Padding can add up to one full block to the output.
        let outputCapacity = input.count + kCCBlockSizeAES128
        var output = [UInt8](repeating: 0, count: outputCapacity)
        var outputByteCount = 0
        let status = input.withUnsafeBytes { inputBuffer in
            encryptionKey.withUnsafeBytes { keyBuffer in
                initializationVector.withUnsafeBytes { vectorBuffer in
                    CCCrypt(
                        operation,
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBuffer.baseAddress,
                        encryptionKey.count,
                        vectorBuffer.baseAddress,
                        inputBuffer.baseAddress,
                        input.count,
                        &output,
                        outputCapacity,
                        &outputByteCount
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw CryptoError.cipherOperationFailed(status: status)
        }
        return Data(output.prefix(outputByteCount))
    }
}

public enum RandomBytes {
    public static func generate(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw CryptoError.randomGenerationFailed(status: status)
        }
        return Data(bytes)
    }
}
