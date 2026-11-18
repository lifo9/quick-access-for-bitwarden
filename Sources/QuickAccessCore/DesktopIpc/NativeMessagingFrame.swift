import Foundation

/// The framing of browser native messaging, which the desktop app's `desktop_proxy` speaks on its
/// standard input and output: a 32 bit length in native byte order, then that many bytes of JSON.
public enum NativeMessagingFrame {
    /// The largest message the proxy accepts.
    public static let maxPayloadByteCount = 1024 * 1024
    private static let lengthPrefixByteCount = MemoryLayout<UInt32>.size

    public enum FrameError: Error, Equatable {
        case payloadTooLarge(Int)
    }

    public static func encode(payload: Data) throws -> Data {
        guard payload.count <= maxPayloadByteCount else {
            throw FrameError.payloadTooLarge(payload.count)
        }
        return withUnsafeBytes(of: UInt32(payload.count)) { Data($0) } + payload
    }

    /// Splits the bytes received so far into complete payloads and the unfinished rest.
    public static func splitPayloads(from receivedBytes: Data) throws -> (payloads: [Data], remainder: Data) {
        let bytes = [UInt8](receivedBytes)
        var payloads = [Data]()
        var offset = 0
        while bytes.count - offset >= lengthPrefixByteCount {
            let payloadByteCount = Int(
                bytes[offset..<offset + lengthPrefixByteCount].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            )
            guard payloadByteCount <= maxPayloadByteCount else {
                throw FrameError.payloadTooLarge(payloadByteCount)
            }
            let payloadStart = offset + lengthPrefixByteCount
            guard bytes.count - payloadStart >= payloadByteCount else {
                break
            }
            payloads.append(Data(bytes[payloadStart..<payloadStart + payloadByteCount]))
            offset = payloadStart + payloadByteCount
        }
        return (payloads, Data(bytes[offset...]))
    }
}
