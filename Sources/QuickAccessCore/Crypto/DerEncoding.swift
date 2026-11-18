import Foundation

/// The small subset of ASN.1 DER needed to convert RSA keys between the formats Bitwarden stores
/// (PKCS#8 private keys, SubjectPublicKeyInfo public keys) and the PKCS#1 form the Security
/// framework imports and exports.
enum DerEncoding {
    enum Tag: UInt8 {
        case integer = 0x02
        case bitString = 0x03
        case octetString = 0x04
        case null = 0x05
        case objectIdentifier = 0x06
        case sequence = 0x30
    }

    /// Object identifier 1.2.840.113549.1.1.1 (rsaEncryption), content bytes only.
    static let rsaEncryptionObjectIdentifier = Data([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])

    static func encodeElement(tag: Tag, content: Data) -> Data {
        Data([tag.rawValue]) + encodeLength(content.count) + content
    }

    private static func encodeLength(_ length: Int) -> Data {
        guard length >= 0x80 else {
            return Data([UInt8(length)])
        }
        let lengthBytes = withUnsafeBytes(of: UInt64(length).bigEndian) { Data($0) }
            .drop { $0 == 0 }
        return Data([0x80 | UInt8(lengthBytes.count)]) + lengthBytes
    }

    /// Reads consecutive elements out of the content of a constructed element.
    struct Reader {
        private let bytes: [UInt8]
        private var offset = 0

        init(_ data: Data) {
            bytes = [UInt8](data)
        }

        var isAtEnd: Bool {
            offset >= bytes.count
        }

        mutating func readElement(expecting expectedTag: Tag) throws -> Data {
            guard offset < bytes.count, bytes[offset] == expectedTag.rawValue else {
                throw CryptoError.malformedPrivateKey
            }
            offset += 1
            let contentLength = try readLength()
            guard contentLength <= bytes.count - offset else {
                throw CryptoError.malformedPrivateKey
            }
            let content = Data(bytes[offset..<offset + contentLength])
            offset += contentLength
            return content
        }

        private mutating func readLength() throws -> Int {
            guard offset < bytes.count else {
                throw CryptoError.malformedPrivateKey
            }
            let firstByte = bytes[offset]
            offset += 1
            guard firstByte >= 0x80 else {
                return Int(firstByte)
            }
            let numLengthBytes = Int(firstByte & 0x7F)
            // Four length bytes cover 4 GiB, far beyond any key; more would be malformed input.
            guard numLengthBytes >= 1, numLengthBytes <= 4, numLengthBytes <= bytes.count - offset else {
                throw CryptoError.malformedPrivateKey
            }
            let length = bytes[offset..<offset + numLengthBytes].reduce(0) { ($0 << 8) | Int($1) }
            offset += numLengthBytes
            return length
        }
    }
}
