import Foundation

/// Ethereum Keccak-256, NOT NIST SHA3-256. Pure computation only; no key material.
/// Stage 7 independently checks all known vectors against OpenSSL KECCAK-256.
/// This is NOT a signature verifier and MUST NOT authorize sending funds.
enum WalletEVMKeccak256 {
    private static let rate = 136
    private static let rotations: [Int] = [
        0, 1, 62, 28, 27,
        36, 44, 6, 55, 20,
        3, 10, 43, 25, 39,
        41, 45, 15, 21, 8,
        18, 2, 61, 56, 14
    ]
    private static let roundConstants: [UInt64] = [
        0x0000000000000001, 0x0000000000008082,
        0x800000000000808a, 0x8000000080008000,
        0x000000000000808b, 0x0000000080000001,
        0x8000000080008081, 0x8000000000008009,
        0x000000000000008a, 0x0000000000000088,
        0x0000000080008009, 0x000000008000000a,
        0x000000008000808b, 0x800000000000008b,
        0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080,
        0x000000000000800a, 0x800000008000000a,
        0x8000000080008081, 0x8000000000008080,
        0x0000000080000001, 0x8000000080008008
    ]

    @inline(__always) private static func rotate(_ x: UInt64, by amount: Int) -> UInt64 {
        amount == 0 ? x : ((x << amount) | (x >> (64 - amount)))
    }

    private static func permute(_ lanes: inout [UInt64]) {
        for constant in roundConstants {
            var column = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 {
                for y in 0..<5 { column[x] ^= lanes[x + 5*y] }
            }
            for x in 0..<5 {
                let difference = column[(x + 4) % 5] ^ rotate(column[(x + 1) % 5], by: 1)
                for y in 0..<5 { lanes[x + 5*y] ^= difference }
            }
            var rotated = [UInt64](repeating: 0, count: 25)
            for x in 0..<5 {
                for y in 0..<5 {
                    let from = x + 5*y
                    let to = y + 5*((2*x + 3*y) % 5)
                    rotated[to] = rotate(lanes[from], by: rotations[from])
                }
            }
            for x in 0..<5 {
                for y in 0..<5 {
                    lanes[x + 5*y] = rotated[x + 5*y]
                        ^ ((~rotated[(x + 1) % 5 + 5*y]) & rotated[(x + 2) % 5 + 5*y])
                }
            }
            lanes[0] ^= constant
        }
    }

    static func hash(_ data: Data) -> Data {
        var padded = Array(data)
        padded.append(0x01) // Keccak pad10*1 domain, not SHA3's 0x06
        while padded.count % rate != 0 { padded.append(0) }
        // When the suffix lands in the final rate byte, both padding bits
        // belong to the SAME byte (0x81), not an extra absorb block.
        padded[padded.count - 1] |= 0x80

        var lanes = [UInt64](repeating: 0, count: 25)
        for start in stride(from: 0, to: padded.count, by: rate) {
            for index in 0..<rate {
                lanes[index / 8] ^= UInt64(padded[start + index]) << ((index % 8) * 8)
            }
            permute(&lanes)
        }
        var result = [UInt8](repeating: 0, count: 32)
        for index in 0..<32 {
            result[index] = UInt8(truncatingIfNeeded: lanes[index / 8] >> ((index % 8) * 8))
        }
        return Data(result)
    }

    static func hex(_ data: Data) -> String {
        "0x" + hash(data).map { String(format: "%02x", $0) }.joined()
    }
}
