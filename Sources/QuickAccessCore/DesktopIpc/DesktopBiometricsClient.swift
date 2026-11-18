import Foundation

/// The desktop app's answer to "can this account be unlocked with biometrics right now". The raw
/// values are the desktop app's own.
public enum BiometricsStatus: Int, Sendable, Equatable {
    case available = 0
    /// The desktop app was restarted and needs the master password once before biometrics work.
    case unlockNeeded = 1
    case hardwareUnavailable = 2
    case autoSetupNeeded = 3
    case manualSetupNeeded = 4
    case platformUnsupported = 5
    case desktopDisconnected = 6
    case notEnabledLocally = 7
    case notEnabledInConnectedDesktopApp = 8
    case nativeMessagingPermissionMissing = 9
}

public enum DesktopIpcError: Error, Equatable {
    /// The connection ended, or the time limit passed, before the desktop app answered.
    case noReply
    case accountNotLoggedIntoDesktopApp
    case secureChannelRejected
    case malformedReply
}

public enum BiometricUnlockOutcome: Sendable, Equatable {
    case unlocked(SymmetricCryptoKey)
    /// The Touch ID prompt was cancelled or failed.
    case denied
    case unavailable(BiometricsStatus)
}

/// Asks the running Bitwarden desktop app to unlock an account with biometrics, speaking the
/// protocol of the desktop app's browser integration.
///
/// The exchange, each message a JSON object tagged with this client's `appId`:
/// 1. The client sends `setupEncryption` with a fresh RSA public key.
/// 2. The desktop app answers with a session secret, RSA-OAEP encrypted for that key.
/// 3. Every later request and reply is JSON encrypted with the session secret.
///
/// The desktop app owns the Touch ID prompt and its own settings decide whether it unlocks; this
/// client only receives the resulting user key.
public struct DesktopBiometricsClient: Sendable {
    private static let statusTimeout = Duration.seconds(5)
    /// Long enough for a person to notice the Touch ID prompt and respond to it.
    private static let unlockTimeout = Duration.seconds(60)
    /// The desktop app rejects messages older than this, and so does this client.
    private static let maxMessageAgeSeconds: TimeInterval = 10

    private let transport: any DesktopTransport
    private let appId: String
    private let currentDate: @Sendable () -> Date

    /// - Parameter appId: Identifies this client to the desktop app; any stable unique text.
    public init(
        transport: any DesktopTransport,
        appId: String,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
        self.appId = appId
        self.currentDate = currentDate
    }

    public func requestStatus(userId: String) async throws -> BiometricsStatus {
        try await withTimeLimit(Self.statusTimeout) {
            var conversation = try await openConversation(userId: userId)
            return try await requestStatus(in: &conversation)
        }
    }

    /// Shows the desktop app's Touch ID prompt, if biometric unlock is available for the account.
    public func requestUnlock(userId: String) async throws -> BiometricUnlockOutcome {
        try await withTimeLimit(Self.unlockTimeout) {
            var conversation = try await openConversation(userId: userId)
            let status = try await requestStatus(in: &conversation)
            guard status == .available else {
                return .unavailable(status)
            }
            let reply = try await conversation.request(command: "unlockWithBiometricsForUser")
            guard reply.response == .flag(true), let encodedUserKey = reply.userKeyB64 else {
                return .denied
            }
            return .unlocked(try SymmetricCryptoKey(base64Encoded: encodedUserKey))
        }
    }

    private func requestStatus(in conversation: inout Conversation) async throws -> BiometricsStatus {
        let reply = try await conversation.request(command: "getBiometricsStatusForUser")
        guard case .number(let rawStatus) = reply.response, let status = BiometricsStatus(rawValue: rawStatus) else {
            throw DesktopIpcError.malformedReply
        }
        return status
    }

    /// Closing the transport ends the stream of received messages, which is what makes a waiting
    /// conversation give up. The transport is closed either way: a conversation is not reused.
    private func withTimeLimit<Outcome>(
        _ timeLimit: Duration,
        _ converse: () async throws -> Outcome
    ) async throws -> Outcome {
        let transport = transport
        let watchdog = Task {
            try await Task.sleep(for: timeLimit)
            transport.close()
        }
        defer {
            watchdog.cancel()
            transport.close()
        }
        return try await converse()
    }

    private func openConversation(userId: String) async throws -> Conversation {
        var payloadIterator = transport.receivedPayloads.makeAsyncIterator()
        let (privateKey, subjectPublicKeyInfo) = try RsaCipher.generateKeyPair()

        // The proxy announces when it has reached the desktop app's socket.
        try await Self.waitForEnvelope(from: &payloadIterator) { envelope, _ in
            envelope.command == "connected" ? () : nil
        }

        let handshake = OuterMessage(
            appId: appId,
            message: SetupEncryptionMessage(
                command: "setupEncryption",
                publicKey: subjectPublicKeyInfo.base64EncodedString(),
                userId: userId,
                messageId: 0,
                timestamp: Self.millisecondsSince1970(currentDate())
            )
        )
        try transport.send(payload: JSONEncoder().encode(handshake))

        let appId = appId
        let sessionSecret = try await Self.waitForEnvelope(from: &payloadIterator) {
            envelope, payload -> SymmetricCryptoKey? in
            // The desktop app broadcasts to all its clients; messages for others are not ours.
            guard envelope.appId == appId else {
                return nil
            }
            if envelope.command == "wrongUserId" {
                throw DesktopIpcError.accountNotLoggedIntoDesktopApp
            }
            guard envelope.command == "setupEncryption" else {
                return nil
            }
            let reply = try JSONDecoder().decode(SetupEncryptionReply.self, from: payload)
            guard let wrappedSecret = Data(base64Encoded: reply.sharedSecret) else {
                throw DesktopIpcError.malformedReply
            }
            let encodedSecret = try RsaCipher.decrypt(.rsa2048OaepSha1(ciphertext: wrappedSecret), with: privateKey)
            return try SymmetricCryptoKey(encodedKey: encodedSecret)
        }

        return Conversation(
            transport: transport,
            payloadIterator: payloadIterator,
            appId: appId,
            userId: userId,
            sessionSecret: sessionSecret,
            currentDate: currentDate
        )
    }

    /// Reads messages until `extract` returns a value for one of them.
    private static func waitForEnvelope<Extracted>(
        from payloadIterator: inout AsyncStream<Data>.Iterator,
        extract: (Envelope, Data) throws -> Extracted?
    ) async throws -> Extracted {
        while let payload = await payloadIterator.next() {
            // Anything that is not a JSON object with the expected shape is someone else's.
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: payload) else {
                continue
            }
            if let extracted = try extract(envelope, payload) {
                return extracted
            }
        }
        throw DesktopIpcError.noReply
    }

    private static func millisecondsSince1970(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }

    /// The encrypted part of the exchange. Used by one task from start to end.
    private struct Conversation {
        let transport: any DesktopTransport
        var payloadIterator: AsyncStream<Data>.Iterator
        let appId: String
        let userId: String
        let sessionSecret: SymmetricCryptoKey
        let currentDate: @Sendable () -> Date
        /// Starts at a random number: the desktop app answers a client id under its latest
        /// session, so a late reply to an earlier conversation could otherwise carry the
        /// number this one is waiting for.
        var nextMessageId = Int.random(in: 1...1_000_000_000)

        mutating func request(command: String) async throws -> CommandReply {
            let messageId = nextMessageId
            nextMessageId += 1

            let request = CommandRequest(
                command: command,
                userId: userId,
                messageId: messageId,
                timestamp: DesktopBiometricsClient.millisecondsSince1970(currentDate())
            )
            let encryptedRequest = try SymmetricCipher.encrypt(
                JSONEncoder().encode(request),
                with: sessionSecret,
                initializationVector: RandomBytes.generate(count: SymmetricCipher.initializationVectorByteCount)
            )
            let outerMessage = OuterMessage(appId: appId, message: EncryptedPayload(encryptedRequest))
            try transport.send(payload: JSONEncoder().encode(outerMessage))

            let appId = appId
            let sessionSecret = sessionSecret
            let currentDate = currentDate
            return try await DesktopBiometricsClient.waitForEnvelope(from: &payloadIterator) {
                envelope, payload -> CommandReply? in
                guard envelope.appId == appId else {
                    return nil
                }
                if envelope.command == "invalidateEncryption" {
                    throw DesktopIpcError.secureChannelRejected
                }
                guard let encryptedReply = try? JSONDecoder().decode(EncryptedReply.self, from: payload) else {
                    return nil
                }
                let replyJson = try SymmetricCipher.decrypt(encryptedReply.message.encryptedString, with: sessionSecret)
                let reply = try JSONDecoder().decode(CommandReply.self, from: replyJson)
                let replyAgeSeconds = abs(currentDate().timeIntervalSince1970 - TimeInterval(reply.timestamp) / 1000)
                let isFreshAnswerToThisRequest =
                    reply.messageId == messageId
                    && replyAgeSeconds <= DesktopBiometricsClient.maxMessageAgeSeconds
                return isFreshAnswerToThisRequest ? reply : nil
            }
        }
    }
}

// MARK: - Wire format

/// The properties every message from the desktop app or its proxy may carry.
private struct Envelope: Decodable {
    let command: String?
    let appId: String?
}

private struct OuterMessage<Message: Encodable>: Encodable {
    let appId: String
    let message: Message
}

private struct SetupEncryptionMessage: Encodable {
    let command: String
    let publicKey: String
    let userId: String
    let messageId: Int
    let timestamp: Int64
}

private struct SetupEncryptionReply: Decodable {
    let sharedSecret: String
}

private struct CommandRequest: Encodable {
    let command: String
    let userId: String
    let messageId: Int
    let timestamp: Int64
}

private struct CommandReply: Decodable {
    /// `response` is a yes/no for unlock requests and a status number for status requests.
    enum Response: Decodable, Equatable {
        case flag(Bool)
        case number(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let flag = try? container.decode(Bool.self) {
                self = .flag(flag)
            } else {
                self = .number(try container.decode(Int.self))
            }
        }
    }

    let messageId: Int
    let timestamp: Int64
    let response: Response?
    let userKeyB64: String?
}

private struct EncryptedReply: Decodable {
    let message: EncryptedPayload
}

/// An encrypted string as the desktop app exchanges it over IPC: an object with the serialized
/// form and its parts. Older versions sent the serialized form alone, which is accepted too.
private struct EncryptedPayload: Codable {
    let encryptedString: EncryptedString

    init(_ encryptedString: EncryptedString) {
        self.encryptedString = encryptedString
    }

    private enum CodingKeys: String, CodingKey {
        case encryptedString
        case encryptionType
        case data
        case iv
        case mac
    }

    init(from decoder: Decoder) throws {
        if let serialized = try? decoder.singleValueContainer().decode(String.self) {
            encryptedString = try EncryptedString(serialized: serialized)
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            encryptedString = try EncryptedString(serialized: container.decode(String.self, forKey: .encryptedString))
        }
    }

    func encode(to encoder: Encoder) throws {
        guard
            case .aesCbc256HmacSha256(let initializationVector, let ciphertext, let authenticationCode) =
                encryptedString
        else {
            throw CryptoError.unsupportedEncryptionType("only symmetric values are sent over IPC")
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(encryptedString.serialized, forKey: .encryptedString)
        try container.encode(2, forKey: .encryptionType)
        try container.encode(ciphertext.base64EncodedString(), forKey: .data)
        try container.encode(initializationVector.base64EncodedString(), forKey: .iv)
        try container.encode(authenticationCode.base64EncodedString(), forKey: .mac)
    }
}
