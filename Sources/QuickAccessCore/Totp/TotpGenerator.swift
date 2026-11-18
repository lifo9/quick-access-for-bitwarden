import CryptoKit
import Foundation

public enum TotpError: Error, Equatable {
    case malformedSecret
    /// The key asks for something this generator does not implement.
    case unsupportedParameters
}

public enum TotpAlgorithm: Sendable, Equatable {
    case sha1
    case sha256
    case sha512
}

/// The parameters of a one-time code, parsed from the value Bitwarden stores in a login's
/// "authenticator key": a bare Base32 secret, an `otpauth://` URI or a `steam://` URI.
public struct TotpConfiguration: Sendable, Equatable {
    public let secret: Data
    public let algorithm: TotpAlgorithm
    public let numDigits: Int
    public let periodSeconds: Int
    /// Steam Guard codes use their own alphabet instead of decimal digits.
    public let usesSteamAlphabet: Bool

    private static let steamUriPrefix = "steam://"
    private static let otpauthUriPrefix = "otpauth://"

    public init(authenticatorKey: String) throws {
        let trimmedKey = authenticatorKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.lowercased().hasPrefix(Self.steamUriPrefix) {
            secret = try Base32.decode(String(trimmedKey.dropFirst(Self.steamUriPrefix.count)))
            algorithm = .sha1
            numDigits = 5
            periodSeconds = 30
            usesSteamAlphabet = true
        } else if trimmedKey.lowercased().hasPrefix(Self.otpauthUriPrefix) {
            let uriComponents = URLComponents(string: trimmedKey)
            // Counter-based keys (`otpauth://hotp/`) need a counter this app does not keep.
            guard uriComponents?.host?.lowercased() == "totp" else {
                throw TotpError.unsupportedParameters
            }
            let queryItems = uriComponents?.queryItems ?? []
            let valuesByParameter = Dictionary(
                queryItems.map { ($0.name.lowercased(), $0.value ?? "") },
                uniquingKeysWith: { firstValue, _ in firstValue }
            )
            guard let encodedSecret = valuesByParameter["secret"] else {
                throw TotpError.malformedSecret
            }
            secret = try Base32.decode(encodedSecret)
            // A parameter that is present but not understood is refused: a code computed with
            // a guessed algorithm, length or period would be wrong without anyone noticing.
            switch valuesByParameter["algorithm"]?.lowercased() {
            case nil, "sha1": algorithm = .sha1
            case "sha256": algorithm = .sha256
            case "sha512": algorithm = .sha512
            default: throw TotpError.unsupportedParameters
            }
            numDigits = try Self.parseParameter(valuesByParameter["digits"], default: 6, allowed: 1...10)
            periodSeconds = try Self.parseParameter(valuesByParameter["period"], default: 30, allowed: 1...86_400)
            usesSteamAlphabet = false
        } else {
            secret = try Base32.decode(trimmedKey)
            algorithm = .sha1
            numDigits = 6
            periodSeconds = 30
            usesSteamAlphabet = false
        }
    }

    private static func parseParameter(
        _ text: String?,
        default defaultNumber: Int,
        allowed allowedNumbers: ClosedRange<Int>
    ) throws -> Int {
        guard let text else {
            return defaultNumber
        }
        guard let number = Int(text), allowedNumbers.contains(number) else {
            throw TotpError.unsupportedParameters
        }
        return number
    }
}

/// Time-based one-time passwords (RFC 6238).
public enum TotpGenerator {
    private static let steamAlphabet = Array("23456789BCDFGHJKMNPQRTVWXY")

    public static func generateCode(configuration: TotpConfiguration, at date: Date) -> String {
        let timeStep = UInt64(max(0, date.timeIntervalSince1970)) / UInt64(configuration.periodSeconds)
        let counterBytes = withUnsafeBytes(of: timeStep.bigEndian) { Data($0) }
        let secretKey = SymmetricKey(data: configuration.secret)
        let digest: [UInt8] =
            switch configuration.algorithm {
            case .sha1: Array(HMAC<Insecure.SHA1>.authenticationCode(for: counterBytes, using: secretKey))
            case .sha256: Array(HMAC<SHA256>.authenticationCode(for: counterBytes, using: secretKey))
            case .sha512: Array(HMAC<SHA512>.authenticationCode(for: counterBytes, using: secretKey))
            }

        // Dynamic truncation (RFC 4226): the low nibble of the last byte picks four bytes, whose
        // top bit is dropped to get a positive 31 bit number.
        let truncationOffset = Int(digest[digest.count - 1] & 0x0F)
        let truncatedNumber =
            digest[truncationOffset..<truncationOffset + 4]
            .reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } & 0x7FFF_FFFF

        if configuration.usesSteamAlphabet {
            let characterIndices = sequence(first: Int(truncatedNumber)) { $0 / steamAlphabet.count }
                .prefix(configuration.numDigits)
                .map { $0 % steamAlphabet.count }
            return String(characterIndices.map { steamAlphabet[$0] })
        }
        let modulus = (0..<configuration.numDigits).reduce(UInt64(1)) { power, _ in power * 10 }
        let code = String(UInt64(truncatedNumber) % modulus)
        return String(repeating: "0", count: configuration.numDigits - code.count) + code
    }

    public static func secondsRemaining(configuration: TotpConfiguration, at date: Date) -> Int {
        configuration.periodSeconds - Int(max(0, date.timeIntervalSince1970)) % configuration.periodSeconds
    }
}

enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    private static let valuesByCharacter = Dictionary(
        uniqueKeysWithValues: alphabet.enumerated().map { ($1, UInt32($0)) }
    )

    /// Decodes RFC 4648 Base32, tolerating what people paste: lower case, spaces, dashes and
    /// missing padding.
    static func decode(_ encoded: String) throws -> Data {
        let characters = encoded.uppercased().filter { !" -=\n\t".contains($0) }
        guard !characters.isEmpty else {
            throw TotpError.malformedSecret
        }
        var decodedBytes = [UInt8]()
        var bitBuffer: UInt32 = 0
        var numBufferedBits = 0
        for character in characters {
            guard let characterValue = valuesByCharacter[character] else {
                throw TotpError.malformedSecret
            }
            bitBuffer = (bitBuffer << 5) | characterValue
            numBufferedBits += 5
            if numBufferedBits >= 8 {
                numBufferedBits -= 8
                decodedBytes.append(UInt8((bitBuffer >> UInt32(numBufferedBits)) & 0xFF))
                // Keep only the bits not consumed yet, so the buffer cannot overflow.
                bitBuffer &= (1 << UInt32(numBufferedBits)) - 1
            }
        }
        return Data(decodedBytes)
    }
}
