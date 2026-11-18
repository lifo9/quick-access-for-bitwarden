import Foundation
import QuickAccessTestSupport
import XCTest

@testable import QuickAccessCore

/// Plays the Bitwarden desktop app's side of the browser integration protocol, with this
/// package's own primitives, so the client is tested through its real wire format.
private final class FakeDesktopApp: DesktopTransport, @unchecked Sendable {
    struct Behavior {
        var loggedInUserIds: Set<String> = [DesktopBiometricsClientTests.userId]
        var biometricsStatus = BiometricsStatus.available
        /// `nil` plays a cancelled Touch ID prompt.
        var userKeyToHandOver: SymmetricCryptoKey? = Fixtures.userKey
        var sendsRepliesAsBareSerializedString = false
        var replyAgeSeconds: TimeInterval = 0
        var closesConnectionInsteadOfReplying = false
    }

    let receivedPayloads: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let behavior: Behavior
    private let sessionSecret = try! SymmetricCryptoKey(encodedKey: Data(repeating: 3, count: 64))
    private let lock = NSLock()
    private var commands = [String]()
    private var messageIds = [Int]()
    private var closed = false

    var receivedCommands: [String] {
        lock.withLock { commands }
    }

    var receivedMessageIds: [Int] {
        lock.withLock { messageIds }
    }

    var isClosed: Bool {
        lock.withLock { closed }
    }

    init(behavior: Behavior = Behavior()) {
        self.behavior = behavior
        (receivedPayloads, continuation) = AsyncStream.makeStream(of: Data.self)
        // What `desktop_proxy` reports once it has reached the desktop app.
        emit(["command": "connected"])
    }

    func close() {
        lock.withLock { closed = true }
        continuation.finish()
    }

    func send(payload: Data) throws {
        let outerMessage = try JSONSerialization.jsonObject(with: payload) as! [String: Any]
        let appId = outerMessage["appId"] as! String
        let message = outerMessage["message"] as! [String: Any]

        if message["command"] as? String == "setupEncryption" {
            try answerSetupEncryption(message, appId: appId)
        } else {
            try answerEncryptedCommand(message, appId: appId)
        }
    }

    private func answerSetupEncryption(_ message: [String: Any], appId: String) throws {
        guard behavior.loggedInUserIds.contains(message["userId"] as! String) else {
            emit(["command": "wrongUserId", "appId": appId])
            return
        }
        // The desktop app broadcasts to every connected client, so others' messages arrive too.
        emit(["command": "setupEncryption", "appId": "another-client", "sharedSecret": "AAAA"])
        let wrappedSecret = try Fixtures.rsaEncrypt(
            sessionSecret.encodedKey,
            subjectPublicKeyInfo: Fixtures.decodeBase64(message["publicKey"] as! String)
        )
        emit([
            "command": "setupEncryption",
            "appId": appId,
            "messageId": -1,
            "sharedSecret": wrappedSecret.base64EncodedString(),
        ])
    }

    private func answerEncryptedCommand(_ encryptedMessage: [String: Any], appId: String) throws {
        let requestJson = try SymmetricCipher.decrypt(
            EncryptedString(serialized: encryptedMessage["encryptedString"] as! String),
            with: sessionSecret
        )
        let request = try JSONSerialization.jsonObject(with: requestJson) as! [String: Any]
        let command = request["command"] as! String
        lock.withLock {
            commands.append(command)
            messageIds.append(request["messageId"] as! Int)
        }

        guard !behavior.closesConnectionInsteadOfReplying else {
            close()
            return
        }

        let replyTimestamp = Int64((Date().timeIntervalSince1970 - behavior.replyAgeSeconds) * 1000)
        let commandResult: [String: Any] =
            switch command {
            case "getBiometricsStatusForUser":
                ["response": behavior.biometricsStatus.rawValue]
            case "unlockWithBiometricsForUser":
                behavior.userKeyToHandOver.map {
                    ["response": true, "userKeyB64": $0.encodedKey.base64EncodedString()]
                }
                    ?? ["response": false]
            default:
                fatalError("the fake desktop app does not know the command \(command)")
            }
        let reply = commandResult.merging([
            "command": command,
            "messageId": request["messageId"] as! Int,
            "timestamp": replyTimestamp,
        ]) { _, envelopeValue in envelopeValue }

        let serializedReply = Fixtures.encrypt(try JSONSerialization.data(withJSONObject: reply), with: sessionSecret)
        let encryptedReply: Any =
            behavior.sendsRepliesAsBareSerializedString
            ? serializedReply
            : ["encryptedString": serializedReply, "encryptionType": 2]
        emit(["appId": appId, "messageId": request["messageId"] as! Int, "message": encryptedReply])
        if behavior.replyAgeSeconds != 0 {
            // Nothing else will come; ending the stream keeps the test from waiting for a timeout.
            close()
        }
    }

    private func emit(_ message: [String: Any]) {
        continuation.yield(try! JSONSerialization.data(withJSONObject: message))
    }
}

final class DesktopBiometricsClientTests: XCTestCase {
    static let userId = "11111111-2222-3333-4444-555555555555"

    private func makeClient(_ desktopApp: FakeDesktopApp) -> DesktopBiometricsClient {
        DesktopBiometricsClient(transport: desktopApp, appId: "quick-access-test")
    }

    func test_requestUnlock__returnsUserKeyAfterDesktopApproves() async throws {
        let desktopApp = FakeDesktopApp()

        let outcome = try await makeClient(desktopApp).requestUnlock(userId: Self.userId)

        XCTAssertEqual(outcome, .unlocked(Fixtures.userKey))
        XCTAssertEqual(desktopApp.receivedCommands, ["getBiometricsStatusForUser", "unlockWithBiometricsForUser"])
        XCTAssertTrue(desktopApp.isClosed)
    }

    func test_requestUnlock__returnsDeniedWhenTouchIdIsCancelled() async throws {
        let desktopApp = FakeDesktopApp(behavior: .init(userKeyToHandOver: nil))

        let outcome = try await makeClient(desktopApp).requestUnlock(userId: Self.userId)

        XCTAssertEqual(outcome, .denied)
    }

    func test_requestUnlock__doesNotPromptWhenDesktopNeedsMasterPasswordFirst() async throws {
        let desktopApp = FakeDesktopApp(behavior: .init(biometricsStatus: .unlockNeeded))

        let outcome = try await makeClient(desktopApp).requestUnlock(userId: Self.userId)

        XCTAssertEqual(outcome, .unavailable(.unlockNeeded))
        XCTAssertEqual(desktopApp.receivedCommands, ["getBiometricsStatusForUser"])
    }

    func test_requestUnlock__throwsWhenAccountIsNotLoggedIntoDesktopApp() async throws {
        let desktopApp = FakeDesktopApp(behavior: .init(loggedInUserIds: ["someone-else"]))

        do {
            _ = try await makeClient(desktopApp).requestUnlock(userId: Self.userId)
            XCTFail("expected the unlock request to throw")
        } catch {
            XCTAssertEqual(error as? DesktopIpcError, .accountNotLoggedIntoDesktopApp)
        }
        XCTAssertTrue(desktopApp.isClosed)
    }

    func test_requestUnlock__acceptsReplySentAsBareSerializedString() async throws {
        let desktopApp = FakeDesktopApp(behavior: .init(sendsRepliesAsBareSerializedString: true))

        let outcome = try await makeClient(desktopApp).requestUnlock(userId: Self.userId)

        XCTAssertEqual(outcome, .unlocked(Fixtures.userKey))
    }

    func test_requestStatus__returnsStatusReportedByDesktop() async throws {
        let desktopApp = FakeDesktopApp(behavior: .init(biometricsStatus: .notEnabledInConnectedDesktopApp))

        let status = try await makeClient(desktopApp).requestStatus(userId: Self.userId)

        XCTAssertEqual(status, .notEnabledInConnectedDesktopApp)
    }

    func test_requestStatus__numbersItsRequestsDifferentlyInEveryConversation() async throws {
        // The desktop app answers a client id under its latest session, so a late reply to an
        // earlier conversation must not carry a number the current one is waiting for.
        let firstDesktopApp = FakeDesktopApp()
        let secondDesktopApp = FakeDesktopApp()

        _ = try await makeClient(firstDesktopApp).requestStatus(userId: Self.userId)
        _ = try await makeClient(secondDesktopApp).requestStatus(userId: Self.userId)

        XCTAssertEqual(firstDesktopApp.receivedMessageIds.count, 1)
        XCTAssertNotEqual(firstDesktopApp.receivedMessageIds, secondDesktopApp.receivedMessageIds)
    }

    func test_requestStatus__throwsNoReplyWhenDesktopClosesTheConnection() async throws {
        let desktopApp = FakeDesktopApp(behavior: .init(closesConnectionInsteadOfReplying: true))

        do {
            _ = try await makeClient(desktopApp).requestStatus(userId: Self.userId)
            XCTFail("expected the status request to throw")
        } catch {
            XCTAssertEqual(error as? DesktopIpcError, .noReply)
        }
    }

    func test_requestStatus__ignoresReplyOlderThanTenSeconds() async throws {
        let desktopApp = FakeDesktopApp(behavior: .init(replyAgeSeconds: 60))

        do {
            _ = try await makeClient(desktopApp).requestStatus(userId: Self.userId)
            XCTFail("expected the stale reply to be ignored")
        } catch {
            XCTAssertEqual(error as? DesktopIpcError, .noReply)
        }
    }
}

final class NativeMessagingFrameTests: XCTestCase {
    func test_encode__prefixesPayloadWithItsLength() throws {
        let frame = try NativeMessagingFrame.encode(payload: Data("{}".utf8))

        // Both Mac architectures are little endian, which is the native order the proxy expects.
        XCTAssertEqual([UInt8](frame), [2, 0, 0, 0, 0x7B, 0x7D])
    }

    func test_splitPayloads__returnsCompletePayloadsAndKeepsTheUnfinishedRest() throws {
        let firstFrame = try NativeMessagingFrame.encode(payload: Data("first".utf8))
        let secondFrame = try NativeMessagingFrame.encode(payload: Data("second".utf8))
        let receivedBytes = firstFrame + secondFrame + secondFrame.prefix(7)

        let (payloads, remainder) = try NativeMessagingFrame.splitPayloads(from: receivedBytes)

        XCTAssertEqual(payloads.map { String(decoding: $0, as: UTF8.self) }, ["first", "second"])
        XCTAssertEqual(remainder, Data(secondFrame.prefix(7)))
    }

    func test_splitPayloads__throwsWhenLengthExceedsWhatTheProxySends() throws {
        let oversizedFrame = Data([0xFF, 0xFF, 0xFF, 0x7F]) + Data("x".utf8)

        XCTAssertThrowsError(try NativeMessagingFrame.splitPayloads(from: oversizedFrame))
    }
}
