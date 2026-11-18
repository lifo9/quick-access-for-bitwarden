import Foundation

/// A message channel to the running Bitwarden desktop app.
public protocol DesktopTransport: Sendable {
    /// The JSON payloads received from the desktop app, one per message. The stream ends when the
    /// connection closes.
    var receivedPayloads: AsyncStream<Data> { get }

    func send(payload: Data) throws

    func close()
}

/// Reaches the desktop app the way its browser extension does: through the `desktop_proxy`
/// executable inside the app bundle, which relays native messaging frames on its standard input
/// and output to the desktop app's local socket.
public final class DesktopProxyTransport: DesktopTransport, @unchecked Sendable {
    // `Process` and `FileHandle` lack the Sendable annotation. After `init` this class only calls
    // `terminate`, `close` and `write`, each of which is safe from any thread.
    private let process = Process()
    private let proxyInput = Pipe()
    public let receivedPayloads: AsyncStream<Data>

    public init(proxyExecutable: URL) throws {
        // Without this, writing to a proxy that has already exited kills this process with
        // SIGPIPE instead of failing the write.
        signal(SIGPIPE, SIG_IGN)

        let proxyOutput = Pipe()
        let (receivedPayloads, continuation) = AsyncStream.makeStream(of: Data.self)
        self.receivedPayloads = receivedPayloads
        let frameBuffer = FrameBuffer()
        proxyOutput.fileHandleForReading.readabilityHandler = { outputHandle in
            let receivedBytes = outputHandle.availableData
            // No bytes means end of file: the proxy exited or the desktop app closed the socket.
            guard !receivedBytes.isEmpty, let payloads = try? frameBuffer.append(receivedBytes) else {
                outputHandle.readabilityHandler = nil
                continuation.finish()
                return
            }
            payloads.forEach { continuation.yield($0) }
        }

        process.executableURL = proxyExecutable
        process.standardInput = proxyInput
        process.standardOutput = proxyOutput
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    public func send(payload: Data) throws {
        try proxyInput.fileHandleForWriting.write(contentsOf: NativeMessagingFrame.encode(payload: payload))
    }

    public func close() {
        // Closing its input makes the proxy disconnect from the desktop app by itself; terminating
        // covers a proxy that does not.
        try? proxyInput.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }
    }

    /// Collects the bytes read so far across calls of the pipe's read handler.
    private final class FrameBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var unfinishedBytes = Data()

        func append(_ receivedBytes: Data) throws -> [Data] {
            try lock.withLock {
                let (payloads, remainder) = try NativeMessagingFrame.splitPayloads(from: unfinishedBytes + receivedBytes)
                unfinishedBytes = remainder
                return payloads
            }
        }
    }
}
