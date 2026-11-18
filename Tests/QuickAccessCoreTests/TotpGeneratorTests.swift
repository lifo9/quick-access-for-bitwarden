import Foundation
@testable import QuickAccessCore
import XCTest

final class TotpGeneratorTests: XCTestCase {
    /// The secrets of the RFC 6238 test vectors, Base32 encoded.
    private let sha1Secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
    private let sha256Secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA===="
    private let sha512Secret =
        "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA="

    private func generateCode(authenticatorKey: String, secondsSince1970: TimeInterval) throws -> String {
        TotpGenerator.generateCode(
            configuration: try TotpConfiguration(authenticatorKey: authenticatorKey),
            at: Date(timeIntervalSince1970: secondsSince1970)
        )
    }

    func test_generateCode__matchesRfc6238VectorsForEachAlgorithm() throws {
        let sha1Uri = "otpauth://totp/Example:alice?secret=\(sha1Secret)&digits=8"
        let sha256Uri = "otpauth://totp/Example:alice?secret=\(sha256Secret)&digits=8&algorithm=SHA256"
        let sha512Uri = "otpauth://totp/Example:alice?secret=\(sha512Secret)&digits=8&algorithm=SHA512"

        XCTAssertEqual(try generateCode(authenticatorKey: sha1Uri, secondsSince1970: 59), "94287082")
        XCTAssertEqual(try generateCode(authenticatorKey: sha1Uri, secondsSince1970: 1_111_111_109), "07081804")
        XCTAssertEqual(try generateCode(authenticatorKey: sha256Uri, secondsSince1970: 59), "46119246")
        XCTAssertEqual(try generateCode(authenticatorKey: sha512Uri, secondsSince1970: 59), "90693936")
    }

    func test_generateCode__usesSixDigitsAndThirtySecondsForBareSecret() throws {
        XCTAssertEqual(try generateCode(authenticatorKey: sha1Secret, secondsSince1970: 59), "287082")
        // One second later the next 30 second period has begun.
        XCTAssertNotEqual(try generateCode(authenticatorKey: sha1Secret, secondsSince1970: 60), "287082")
    }

    func test_generateCode__acceptsSecretAsPeoplePasteIt() throws {
        let pastedSecret = " gezd gnbv gy3t qojq gezd gnbv gy3t qojq \n"

        XCTAssertEqual(try generateCode(authenticatorKey: pastedSecret, secondsSince1970: 59), "287082")
    }

    func test_generateCode__honorsPeriodFromUri() throws {
        let sixtySecondUri = "otpauth://totp/Example?secret=\(sha1Secret)&period=60"

        // With a 60 second period, second 59 is still in period 0 and second 60 starts period 1,
        // which the default 30 second period reaches at second 30.
        XCTAssertEqual(
            try generateCode(authenticatorKey: sixtySecondUri, secondsSince1970: 60),
            try generateCode(authenticatorKey: sha1Secret, secondsSince1970: 30)
        )
    }

    func test_generateCode__producesSteamGuardCode() throws {
        // Expected value computed with an independent implementation (Python hmac).
        XCTAssertEqual(try generateCode(authenticatorKey: "steam://\(sha1Secret)", secondsSince1970: 59), "PV9M4")
    }

    func test_TotpConfiguration_init__throwsForSecretThatIsNotBase32() throws {
        for malformedKey in ["", "not-base32-!!!", "otpauth://totp/Example?digits=6"] {
            XCTAssertThrowsError(try TotpConfiguration(authenticatorKey: malformedKey), "accepted \(malformedKey)") { error in
                XCTAssertEqual(error as? TotpError, .malformedSecret)
            }
        }
    }

    func test_secondsRemaining__countsDownToTheNextPeriod() throws {
        let configuration = try TotpConfiguration(authenticatorKey: sha1Secret)

        XCTAssertEqual(TotpGenerator.secondsRemaining(configuration: configuration, at: Date(timeIntervalSince1970: 59)), 1)
        XCTAssertEqual(TotpGenerator.secondsRemaining(configuration: configuration, at: Date(timeIntervalSince1970: 60)), 30)
    }
}
