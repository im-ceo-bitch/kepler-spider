import Foundation

// Block 7 Stage 6: fail-closed STRUCTURAL validation only. Does not verify
// secp256k1 recovery or keccak256. It MUST NOT authorize broadcasting.
enum WalletEVMEnvelopeError: Error, Equatable {
    case invalidEncoding, wrongNetwork, mismatchedIntent, invalidSignature
}

struct WalletEVMFingerprints: Equatable {
    let transactionHash: String
    let signingDigest: String
}

enum WalletEVMSignedEnvelopeGuard {
    indirect enum Node { case bytes(Data), list([Node]) }

    private static func number(_ data: Data) -> UInt64? {
        if data.count > 8 || (data.count > 0 && data.first == 0) { return nil }
        var value: UInt64 = 0
        for byte in data { value = (value << 8) | UInt64(byte) }
        return value
    }

    private static func length(_ bytes: [UInt8], _ index: inout Int, _ count: Int) throws -> Int {
        guard count > 0 && count <= 4 && index + count <= bytes.count,
              bytes[index] != 0 else { throw WalletEVMEnvelopeError.invalidEncoding }
        var result = 0
        for _ in 0..<count { result = (result << 8) | Int(bytes[index]); index += 1 }
        return result
    }

    private static func parse(_ bytes: [UInt8], _ index: inout Int, _ depth: Int) throws -> Node {
        guard depth <= 4 && index < bytes.count else { throw WalletEVMEnvelopeError.invalidEncoding }
        let prefix = Int(bytes[index]); index += 1
        if prefix < 0x80 { return .bytes(Data([UInt8(prefix)])) }
        if prefix <= 0xb7 {
            let length = prefix - 0x80
            guard index + length <= bytes.count else { throw WalletEVMEnvelopeError.invalidEncoding }
            if length == 1 && bytes[index] < 0x80 { throw WalletEVMEnvelopeError.invalidEncoding }
            let output = Data(bytes[index..<index + length]); index += length
            return .bytes(output)
        }
        if prefix <= 0xbf {
            let n = prefix - 0xb7
            let size = try length(bytes, &index, n)
            guard size >= 56 && index + size <= bytes.count else { throw WalletEVMEnvelopeError.invalidEncoding }
            let output = Data(bytes[index..<index + size]); index += size
            return .bytes(output)
        }
        let size: Int
        if prefix <= 0xf7 { size = prefix - 0xc0 }
        else {
            size = try length(bytes, &index, prefix - 0xf7)
            guard size >= 56 else { throw WalletEVMEnvelopeError.invalidEncoding }
        }
        guard index + size <= bytes.count else { throw WalletEVMEnvelopeError.invalidEncoding }
        let end = index + size
        var children: [Node] = []
        while index < end {
            guard children.count < 16 else { throw WalletEVMEnvelopeError.invalidEncoding }
            children.append(try parse(bytes, &index, depth + 1))
        }
        guard index == end else { throw WalletEVMEnvelopeError.invalidEncoding }
        return .list(children)
    }

    private static func scalar(_ node: Node) throws -> Data {
        guard case .bytes(let data) = node else { throw WalletEVMEnvelopeError.invalidEncoding }
        return data
    }
    private static func same(_ a: Data, _ b: Data) -> Bool { a == b }

    /// Canonical RLP serialization for reconstructing the EIP-1559 signing payload.
    /// Input comes only from `parse`, whose canonical checks reject ambiguous encodings.
    private static func serialize(_ node: Node) -> Data {
        switch node {
        case .bytes(let value):
            if value.count == 1, let byte = value.first, byte < 0x80 { return value }
            return lengthPrefix(value.count, shortBase: 0x80, longBase: 0xb7) + value
        case .list(let items):
            let payload = items.reduce(into: Data()) { $0.append(serialize($1)) }
            return lengthPrefix(payload.count, shortBase: 0xc0, longBase: 0xf7) + payload
        }
    }

    private static func lengthPrefix(_ count: Int, shortBase: UInt8, longBase: UInt8) -> Data {
        if count <= 55 { return Data([shortBase + UInt8(count)]) }
        var size = count
        var encoded = [UInt8]()
        while size > 0 { encoded.insert(UInt8(size & 0xff), at: 0); size >>= 8 }
        return Data([longBase + UInt8(encoded.count)] + encoded)
    }

    /// Read-only chain inspector, for isolated Sepolia Wallet Core vector tests.
    /// A syntactically valid chain ID does NOT validate a signature or transfer.
    static func inspectChainID(raw: Data) throws -> UInt64 {
        guard raw.count >= 70, raw.count <= 2_048, raw.first == 0x02 else {
            throw WalletEVMEnvelopeError.invalidEncoding
        }
        let body = Array(raw.dropFirst())
        var index = 0
        let decoded = try parse(body, &index, 0)
        guard index == body.count, case .list(let fields) = decoded, fields.count == 12,
              Data([0x02]) + serialize(decoded) == raw,
              let network = try number(scalar(fields[0])) else {
            throw WalletEVMEnvelopeError.invalidEncoding
        }
        return network
    }

    /// Stage 7: EIP-1559 raw transaction hash and the digest signed by Wallet Core.
    /// Hashes do NOT prove secp256k1 validity, signer identity, or blockchain acceptance.
    /// Requires successful field-by-field verification against an immutable mainnet intent.
    static func fingerprints(raw: Data, intent: WalletEVMUnsignedIntent) throws -> WalletEVMFingerprints {
        try validate(raw: raw, intent: intent)
        let body = Array(raw.dropFirst())
        var cursor = 0
        let tree = try parse(body, &cursor, 0)
        guard cursor == body.count, case .list(let fields) = tree, fields.count == 12 else {
            throw WalletEVMEnvelopeError.invalidEncoding
        }
        let unsigned = Data([0x02]) + serialize(.list(Array(fields.prefix(9))))
        // Defensive equality: reconstruct full canonical RLP and demand byte equality.
        guard Data([0x02]) + serialize(tree) == raw else {
            throw WalletEVMEnvelopeError.invalidEncoding
        }
        return WalletEVMFingerprints(transactionHash: WalletEVMKeccak256.hex(raw),
                                     signingDigest: WalletEVMKeccak256.hex(unsigned))
    }

    // Pure RLP inspection without a signature validity claim.
    static func validate(raw: Data, intent: WalletEVMUnsignedIntent) throws {
        guard raw.count >= 70 && raw.count <= 2_048 && raw.first == 2 else {
            throw WalletEVMEnvelopeError.invalidEncoding
        }
        let body = Array(raw.dropFirst())
        var index = 0
        let tree = try parse(body, &index, 0)
        guard index == body.count, case .list(let fields) = tree, fields.count == 12 else {
            throw WalletEVMEnvelopeError.invalidEncoding
        }
        guard try number(scalar(fields[0])) == 1 else { throw WalletEVMEnvelopeError.wrongNetwork }
        let nonce = try number(scalar(fields[1]))
        let priority = try number(scalar(fields[2]))
        let maximum = try number(scalar(fields[3]))
        let gas = try number(scalar(fields[4]))
        let destination = try scalar(fields[5])
        let ethValue = try scalar(fields[6])
        let call = try scalar(fields[7])
        let expectedDestination = try WalletEVMSigningBytes.hex(intent.transactionTarget)
        let expectedAmount = intent.asset == .eth ? try WalletEVMSigningBytes.decimal(intent.baseUnits) : Data()
        let expectedCall = intent.asset == .eth ? Data() : try WalletEVMSigningBytes.hex(intent.tokenCallData ?? "", maxBytes: 128)
        guard nonce == intent.nonce, priority == intent.priorityFeePerGas,
              maximum == intent.maxFeePerGas, gas == intent.gasLimit,
              same(destination, expectedDestination), same(ethValue, expectedAmount),
              same(call, expectedCall) else { throw WalletEVMEnvelopeError.mismatchedIntent }
        guard case .list(let access) = fields[8], access.isEmpty,
              let parity = try number(scalar(fields[9])), parity <= 1 else {
            throw WalletEVMEnvelopeError.invalidEncoding
        }
        let r = try scalar(fields[10]), s = try scalar(fields[11])
        let halfOrder: [UInt8] = [0x7f,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,
                                0x5d,0x57,0x6e,0x73,0x5a,0x45,0x01,0xdd,0xfe,0x92,0xf4,0x66,0x81,0xb2,0x0a,0xa0]
        func positive(_ value: Data) -> Bool {
            value.count > 0 && value.count <= 32 && value.first != 0 && value.contains(where: { $0 != 0 })
        }
        let paddedS = Array(repeating: UInt8(0), count: 32 - min(32, s.count)) + s
        guard positive(r), positive(s), paddedS.lexicographicallyPrecedes(halfOrder) || paddedS == halfOrder else {
            throw WalletEVMEnvelopeError.invalidSignature
        }
    }
}
