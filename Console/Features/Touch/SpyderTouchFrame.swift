import Foundation

/// Bounded length-prefixed TCP framing; network callbacks may split/coalesce packets.
struct SpyderTouchFrame {
    static let maximum = 4096
    private var buffer = Data()
    enum Failure: Error { case invalid }

    static func encode(_ payload: Data) throws -> Data {
        guard !payload.isEmpty, payload.count <= maximum else { throw Failure.invalid }
        let n = UInt32(payload.count)
        return Data([UInt8(n >> 24), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)]) + payload
    }

    mutating func append(_ data: Data) throws -> [Data] {
        // Receive calls are capped at maximum+4. Never retain unbounded remote input.
        guard data.count <= Self.maximum + 4 else { throw Failure.invalid }
        buffer.append(data)
        var packets: [Data] = []
        while buffer.count >= 4 {
            let header = Array(buffer.prefix(4))
            let length = header.reduce(0) { ($0 << 8) | Int($1) }
            guard length > 0, length <= Self.maximum else { throw Failure.invalid }
            guard buffer.count >= length + 4 else { break }
            packets.append(Data(buffer.dropFirst(4).prefix(length)))
            buffer = Data(buffer.dropFirst(length + 4))
        }
        guard buffer.count <= Self.maximum + 4 else { throw Failure.invalid }
        return packets
    }
}
