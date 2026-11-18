import Foundation
import Security

/// An RSA private key held by the Security framework, never stored in a keychain.
public struct RsaPrivateKey: @unchecked Sendable {
    // SecKey is an immutable, thread-safe Core Foundation object; it only lacks the annotation.
    let securityKey: SecKey
}

/// RSA-OAEP as Bitwarden uses it: to wrap organization keys for a member's key pair, and to wrap
/// the desktop IPC session secret for a connecting client.
public enum RsaCipher {
    private static let keySizeInBits = 2048

    /// Imports the PKCS#8 private key that Bitwarden stores (encrypted) for the account.
    public static func makePrivateKey(pkcs8DerEncoded: Data) throws -> RsaPrivateKey {
        // The Security framework imports RSA keys in PKCS#1 form only, which PKCS#8 wraps as
        // SEQUENCE { version, SEQUENCE { algorithm, parameters }, OCTET STRING { PKCS#1 key } }.
        var outerReader = DerEncoding.Reader(pkcs8DerEncoded)
        var privateKeyInfoReader = DerEncoding.Reader(try outerReader.readElement(expecting: .sequence))
        _ = try privateKeyInfoReader.readElement(expecting: .integer)
        var algorithmReader = DerEncoding.Reader(try privateKeyInfoReader.readElement(expecting: .sequence))
        let algorithmIdentifier = try algorithmReader.readElement(expecting: .objectIdentifier)
        guard algorithmIdentifier == DerEncoding.rsaEncryptionObjectIdentifier else {
            throw CryptoError.malformedPrivateKey
        }
        let pkcs1PrivateKey = try privateKeyInfoReader.readElement(expecting: .octetString)

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ]
        var unmanagedError: Unmanaged<CFError>?
        guard let securityKey = SecKeyCreateWithData(
            pkcs1PrivateKey as CFData,
            attributes as CFDictionary,
            &unmanagedError
        ) else {
            _ = unmanagedError?.takeRetainedValue()
            throw CryptoError.malformedPrivateKey
        }
        return RsaPrivateKey(securityKey: securityKey)
    }

    public static func decrypt(_ encrypted: EncryptedString, with privateKey: RsaPrivateKey) throws -> Data {
        let algorithm: SecKeyAlgorithm
        let ciphertext: Data
        switch encrypted {
        case let .rsa2048OaepSha1(rsaCiphertext):
            algorithm = .rsaEncryptionOAEPSHA1
            ciphertext = rsaCiphertext
        case let .rsa2048OaepSha256(rsaCiphertext):
            algorithm = .rsaEncryptionOAEPSHA256
            ciphertext = rsaCiphertext
        case .aesCbc256HmacSha256:
            throw CryptoError.unsupportedEncryptionType("symmetric value given to the RSA cipher")
        }
        var unmanagedError: Unmanaged<CFError>?
        guard let plaintext = SecKeyCreateDecryptedData(
            privateKey.securityKey,
            algorithm,
            ciphertext as CFData,
            &unmanagedError
        ) else {
            throw CryptoError.rsaOperationFailed(describe(unmanagedError))
        }
        return plaintext as Data
    }

    /// Generates an in-memory key pair and returns the public half as SubjectPublicKeyInfo DER,
    /// the form the Bitwarden desktop app expects in the IPC handshake.
    public static func generateKeyPair() throws -> (privateKey: RsaPrivateKey, subjectPublicKeyInfo: Data) {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: keySizeInBits,
        ]
        var unmanagedError: Unmanaged<CFError>?
        guard let securityKey = SecKeyCreateRandomKey(attributes as CFDictionary, &unmanagedError) else {
            throw CryptoError.rsaOperationFailed(describe(unmanagedError))
        }
        guard let publicKey = SecKeyCopyPublicKey(securityKey),
              let pkcs1PublicKey = SecKeyCopyExternalRepresentation(publicKey, &unmanagedError)
        else {
            throw CryptoError.rsaOperationFailed(describe(unmanagedError))
        }
        return (
            RsaPrivateKey(securityKey: securityKey),
            encodeSubjectPublicKeyInfo(pkcs1PublicKey: pkcs1PublicKey as Data)
        )
    }

    static func encodeSubjectPublicKeyInfo(pkcs1PublicKey: Data) -> Data {
        let algorithm = DerEncoding.encodeElement(
            tag: .sequence,
            content: DerEncoding.encodeElement(
                tag: .objectIdentifier,
                content: DerEncoding.rsaEncryptionObjectIdentifier
            ) + DerEncoding.encodeElement(tag: .null, content: Data())
        )
        // A BIT STRING starts with the number of unused bits in its last byte, here none.
        let publicKeyBits = DerEncoding.encodeElement(tag: .bitString, content: Data([0x00]) + pkcs1PublicKey)
        return DerEncoding.encodeElement(tag: .sequence, content: algorithm + publicKeyBits)
    }

    private static func describe(_ unmanagedError: Unmanaged<CFError>?) -> String {
        guard let error = unmanagedError?.takeRetainedValue() else {
            return "unknown Security framework error"
        }
        return CFErrorCopyDescription(error) as String
    }
}
