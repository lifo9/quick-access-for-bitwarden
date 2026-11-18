import Foundation
import QuickAccessTestSupport
import XCTest

@testable import QuickAccessCore

final class CryptoTests: XCTestCase {
    private var openSslEncryptedString: EncryptedString {
        .aesCbc256HmacSha256(
            initializationVector: Fixtures.symmetricInitializationVector,
            ciphertext: Fixtures.symmetricCiphertext,
            authenticationCode: Fixtures.symmetricAuthenticationCode
        )
    }

    func test_decryptString__readsValueEncryptedByOpenSsl() throws {
        let plaintext = try SymmetricCipher.decryptString(openSslEncryptedString, with: Fixtures.symmetricKey)

        XCTAssertEqual(plaintext, Fixtures.symmetricPlaintext)
    }

    func test_encrypt__producesSameBytesAsOpenSsl() throws {
        let encrypted = try SymmetricCipher.encrypt(
            Data(Fixtures.symmetricPlaintext.utf8),
            with: Fixtures.symmetricKey,
            initializationVector: Fixtures.symmetricInitializationVector
        )

        XCTAssertEqual(encrypted, openSslEncryptedString)
    }

    func test_decrypt__throwsWhenCiphertextIsTampered() throws {
        var tamperedCiphertext = Fixtures.symmetricCiphertext
        tamperedCiphertext[0] ^= 0x01
        let tampered = EncryptedString.aesCbc256HmacSha256(
            initializationVector: Fixtures.symmetricInitializationVector,
            ciphertext: tamperedCiphertext,
            authenticationCode: Fixtures.symmetricAuthenticationCode
        )

        XCTAssertThrowsError(try SymmetricCipher.decrypt(tampered, with: Fixtures.symmetricKey)) { error in
            XCTAssertEqual(error as? CryptoError, .authenticationFailed)
        }
    }

    func test_decrypt__throwsWhenKeyIsWrong() throws {
        XCTAssertThrowsError(try SymmetricCipher.decrypt(openSslEncryptedString, with: Fixtures.userKey)) { error in
            XCTAssertEqual(error as? CryptoError, .authenticationFailed)
        }
    }

    func test_EncryptedString_init__roundTripsSerializedForm() throws {
        let serialized = openSslEncryptedString.serialized

        XCTAssertTrue(serialized.hasPrefix("2."))
        XCTAssertEqual(try EncryptedString(serialized: serialized), openSslEncryptedString)
    }

    func test_EncryptedString_init__rejectsNewerEncryptionType() throws {
        XCTAssertThrowsError(try EncryptedString(serialized: "7.AAAA")) { error in
            XCTAssertEqual(error as? CryptoError, .unsupportedEncryptionType("7"))
        }
    }

    func test_EncryptedString_init__rejectsMalformedValues() throws {
        for malformed in ["", "plain text", "2.AAAA|AAAA", "2.AAAA|not base64!|AAAA", "4."] {
            XCTAssertThrowsError(try EncryptedString(serialized: malformed), "accepted \(malformed)") { error in
                XCTAssertEqual(error as? CryptoError, .malformedEncryptedString)
            }
        }
    }

    func test_SymmetricCryptoKey_init__rejectsKeyOfWrongLength() throws {
        XCTAssertThrowsError(try SymmetricCryptoKey(encodedKey: Data(count: 32))) { error in
            XCTAssertEqual(error as? CryptoError, .unsupportedKeyLength(32))
        }
    }

    func test_makePrivateKey__importsOpenSslKeyThatUnwrapsOpenSslCiphertext() throws {
        let privateKey = try RsaCipher.makePrivateKey(pkcs8DerEncoded: Fixtures.pkcs8PrivateKey)

        let unwrappedKey = try RsaCipher.decrypt(
            .rsa2048OaepSha1(ciphertext: Fixtures.wrappedOrganizationKey),
            with: privateKey
        )

        XCTAssertEqual(unwrappedKey, Fixtures.organizationKey.encodedKey)
    }

    func test_makePrivateKey__throwsForDataThatIsNotAKey() throws {
        XCTAssertThrowsError(try RsaCipher.makePrivateKey(pkcs8DerEncoded: Data("not a key".utf8))) { error in
            XCTAssertEqual(error as? CryptoError, .malformedPrivateKey)
        }
    }

    func test_encodeSubjectPublicKeyInfo__matchesOpenSslEncoding() throws {
        let encoded = RsaCipher.encodeSubjectPublicKeyInfo(pkcs1PublicKey: Fixtures.pkcs1PublicKey)

        XCTAssertEqual(encoded, Fixtures.subjectPublicKeyInfo)
    }

    func test_generateKeyPair__privateKeyDecryptsWhatThePublicKeyEncrypted() throws {
        let (privateKey, subjectPublicKeyInfo) = try RsaCipher.generateKeyPair()
        let secret = Data("session secret".utf8)

        let ciphertext = try Fixtures.rsaEncrypt(secret, subjectPublicKeyInfo: subjectPublicKeyInfo)

        XCTAssertEqual(try RsaCipher.decrypt(.rsa2048OaepSha1(ciphertext: ciphertext), with: privateKey), secret)
    }
}
