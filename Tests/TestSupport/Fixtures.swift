import Foundation
import QuickAccessCore
import Security

/// Test vectors produced by OpenSSL, so the tests compare this package's cryptography against an
/// independent implementation. The RSA key pair exists only for these tests.
public enum Fixtures {
    public static let pkcs8PrivateKey = decodeBase64(
        """
        MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDXtirBgmYRz1JgPRB3ZUHTCpv+
        ayNxud8KfEmzc0KWTrahI4cFG6cWoXfVQ5jaaU9+r5Rj1L4B4inPOyhI+2nquov+hEhREaQnf8at
        d9fAE4IYDpyeVpkVh58Yd4Mo4iH95krBo2dMeRmZQ0loBSpvs0jUaR44c3UDfg2hh6rfK3Gq3hzy
        Q8gAGK180LIDTz+Fi8f6JJwGxkS2tpLRL3i6gT6a5mpzqqkCOtunG0ee8BNtSMznudu4rTqaLeHi
        hQ1nsgD3Aya+OldYSqwzs2Fr5mseh+ikG5NDEBXXo3hzYybk+qPhkLL9BtKx6RMfn7EckKVihP1z
        XOr7VrBUof57AgMBAAECggEAJOU+K+oLXkl5PAfFzL4vg5LheqNFpTqXCTqX+o8g2QeumiIzAm8n
        5amJjxsoRldT5wXOGkM1mqnd39ms+sqx45mzvz1OBzu+uZjT2TDR4MMVcdrx8+048uNHFY6/itse
        2EgvCi7SSNS/yaSmJhoYF5HxR4+RQTOSVJ4XY8UKN3Bs9KehnEHOmjqCmqzMy2l50hx9p/C9HbyL
        YywMy/og08EU5pzYdic/qBiXoUEozIdsBKkuXdplzx5W8AmsWqMUpG5rHTFdsJkoHDwbfO160tvc
        aZCGjeb9nLr2gOc8y92IZH66OVSjDD7536yFDnVHhcUvX3JxNeiTPuwbdavssQKBgQDthM8cN149
        nqsx2yBUQ7MVVKSsyhIbNXW9slv2FF6FkTwpqiO8AiwazkEATaoWI2Q8hgOLDDJQw0gsPDay1tfe
        DXHzMhRrqd+2NI6glgddL0/h3kPX7iddSqfkAyWXwH0fOnoi9x5F2MZmB7gNgdluvaHSZdC9+UVn
        xtlzPF4YCwKBgQDofvm5MXvQ+KglRC6Ol/gJLVJP4EeN1fJr6kB2tklMRuGQCwSuTmwSmN4akV2B
        g2W7ywburnzCehFAazhpMeWiMSb6FKAaXvUE+jXkJsSPuNgY4SXh6AlBaDI5QWBvbrtRQpZdoU/r
        1jnSVcwEQgnza2XIaQQ19+j3Mrj/EowJUQKBgQDa4SqjC/sSued1WEOgo4qiu4/Nk6G/5TINkBHi
        4b6BQ+e3VYz8stvGEBAioW9+WzsB81XMi37KokseSJb3k7j2bll2Dc53sOHx3Nka72b13qW0tci7
        ckJgXG3/V08LW11yq8bl9ei14SBj4fUgrWqb/LDlXOJSTyZAjiTRZu4nJQKBgEB+mL+q3nIFyH8t
        /sxHk+LX07Gcwbyy0ODmxqMnxgWG1COlKtM/pfMyvMoZ8RpwXNRPacjkVm+MdSStmaR01wK7J9jP
        x+oI1WdgEXsM1hIYcLnWGzAjsg2W3ffMDvhae1P7aMLocMc3Uirq6gF0YFZKQJ3ro+Nkthd81pzL
        hFVBAoGBAK1/Ibn1rjcy1uR20dre+rCwyuNytLfQiQn7FsOCaYq88UiZBX6sege3buqf/XWzsba/
        9ukAyh78BWg1VXkPO0yxpnlE+suiUBnbJFJJq4ae/xaJ5QyCsCFsSSMAxUUQ1hEELTONz0T5iiWE
        bPAKndt8EmPt7wO67zfmZ+FpB/71
        """)

    public static let subjectPublicKeyInfo = decodeBase64(
        """
        MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA17YqwYJmEc9SYD0Qd2VB0wqb/msjcbnf
        CnxJs3NClk62oSOHBRunFqF31UOY2mlPfq+UY9S+AeIpzzsoSPtp6rqL/oRIURGkJ3/GrXfXwBOC
        GA6cnlaZFYefGHeDKOIh/eZKwaNnTHkZmUNJaAUqb7NI1GkeOHN1A34NoYeq3ytxqt4c8kPIABit
        fNCyA08/hYvH+iScBsZEtraS0S94uoE+muZqc6qpAjrbpxtHnvATbUjM57nbuK06mi3h4oUNZ7IA
        9wMmvjpXWEqsM7Nha+ZrHofopBuTQxAV16N4c2Mm5Pqj4ZCy/QbSsekTH5+xHJClYoT9c1zq+1aw
        VKH+ewIDAQAB
        """)

    public static let pkcs1PublicKey = decodeBase64(
        """
        MIIBCgKCAQEA17YqwYJmEc9SYD0Qd2VB0wqb/msjcbnfCnxJs3NClk62oSOHBRunFqF31UOY2mlP
        fq+UY9S+AeIpzzsoSPtp6rqL/oRIURGkJ3/GrXfXwBOCGA6cnlaZFYefGHeDKOIh/eZKwaNnTHkZ
        mUNJaAUqb7NI1GkeOHN1A34NoYeq3ytxqt4c8kPIABitfNCyA08/hYvH+iScBsZEtraS0S94uoE+
        muZqc6qpAjrbpxtHnvATbUjM57nbuK06mi3h4oUNZ7IA9wMmvjpXWEqsM7Nha+ZrHofopBuTQxAV
        16N4c2Mm5Pqj4ZCy/QbSsekTH5+xHJClYoT9c1zq+1awVKH+ewIDAQAB
        """)

    /// The organization key below, wrapped with RSA-OAEP-SHA1 for the key pair above.
    public static let wrappedOrganizationKey = decodeBase64(
        """
        pJdVCyg0OeYXK7beqbGfoUQJDtG5qTJAtp2j9a9pCG4XEvXHPP7iIq6gEPxL6mbc2sH/W5vZfVoM
        R7XjboFnJ1J+Wzw/K8uBZTnqh1yI27zMSK9wSUD4ZpLLl1cNiRC1VyhbtTh1zsSfVDCiaXQc1J5B
        +AHBRmtpw3pfqK6SyWbOVhOtNbwFLbXecm6xJQKOag0upt5w/BowyUrD9GC2Ehus4vN6M1jGs1MO
        s8Drqgd1AvqcIy7Cvty8QuQ9FZw734SKO3zdQfW2n7FgF7vCBFLCzelwYuqjUMxyO3oTikrbL5Rr
        oJ0aYOODL5MECkIYiwSnw+lCs1QXa7pXUc+8Fw==
        """)

    public static let organizationKey = try! SymmetricCryptoKey(encodedKey: Data(100..<164))

    /// AES-256-CBC + HMAC-SHA256 of `symmetricPlaintext` under `symmetricKey`.
    public static let symmetricKey = try! SymmetricCryptoKey(encodedKey: Data(0..<64))
    public static let symmetricPlaintext = "quick access test vector"
    public static let symmetricInitializationVector = Data(200..<216)
    public static let symmetricCiphertext = decodeBase64("+oA38hdXwQKDEaYk3+m8AE3OqkhMXrVyw0VjSM5D+gw=")
    public static let symmetricAuthenticationCode = decodeBase64("buPAfTjNC2+Ggbu2HUs2hrv8ajsIOFfBn1qbIzqzF6E=")

    public static let userKey = try! SymmetricCryptoKey(encodedKey: Data(repeating: 7, count: 64))

    public static func decodeBase64(_ text: String) -> Data {
        Data(base64Encoded: text, options: .ignoreUnknownCharacters)!
    }

    /// Encrypts like Bitwarden does for a type 2 value, with a random initialization vector.
    public static func encrypt(_ text: String, with key: SymmetricCryptoKey) -> String {
        encrypt(Data(text.utf8), with: key)
    }

    public static func encrypt(_ plaintext: Data, with key: SymmetricCryptoKey) -> String {
        let initializationVector = try! RandomBytes.generate(count: SymmetricCipher.initializationVectorByteCount)
        return try! SymmetricCipher.encrypt(plaintext, with: key, initializationVector: initializationVector).serialized
    }

    /// RSA-OAEP-SHA1 encryption for a SubjectPublicKeyInfo public key, the desktop app's side of
    /// the IPC handshake.
    public static func rsaEncrypt(_ plaintext: Data, subjectPublicKeyInfo: Data) throws -> Data {
        // The Security framework imports the bare PKCS#1 key. For a 2048 bit RSA key that is
        // everything after the 24 byte SubjectPublicKeyInfo header.
        let subjectPublicKeyInfoHeaderByteCount = 24
        let pkcs1PublicKey = subjectPublicKeyInfo.dropFirst(subjectPublicKeyInfoHeaderByteCount)
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
        ]
        guard let publicKey = SecKeyCreateWithData(Data(pkcs1PublicKey) as CFData, attributes as CFDictionary, nil),
            let ciphertext = SecKeyCreateEncryptedData(publicKey, .rsaEncryptionOAEPSHA1, plaintext as CFData, nil)
        else {
            throw CryptoError.rsaOperationFailed("test encryption failed")
        }
        return ciphertext as Data
    }
}
