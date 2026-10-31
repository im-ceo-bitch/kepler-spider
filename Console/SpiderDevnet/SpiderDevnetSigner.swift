// Spider Chain testnet signing contract for Spider Wallet (iOS 17+).
// NOTE: the protocol is RESEARCH DEVNET, not stable mainnet.
// Import into Spider Wallet alongside SpiderCertifiedWalletClient.swift.
// Keys are created/stored by the wallet's secure key-management layer.
import Foundation
import CryptoKit

struct SpiderTransferPayload: Codable, Equatable {
    let chain_id: String
    let sender: String
    let recipient: String
    let asset_id: String
    let amount: UInt64             // Integer atomic units, never Double
    let nonce: UInt64
    let gas_limit: UInt64
    let max_fee_per_gas: UInt64
    let expiry_height: UInt64

    func canonicalSigningBytes() -> Data {
        var output = Data("SPIDER/TX/TRANSFER/V1\0".utf8)
        for string in [chain_id, sender, recipient, asset_id] {
            let bytes = Data(string.utf8)
            precondition(bytes.count <= Int(UInt32.max))
            output.appendUInt32BE(UInt32(bytes.count))
            output.append(bytes)
        }
        for value in [amount, nonce, gas_limit, max_fee_per_gas, expiry_height] {
            output.appendUInt64BE(value)
        }
        return output
    }
}

struct SpiderSignedTransfer: Codable {
    let payload: SpiderTransferPayload
    let public_key: String
    let signature: String

    func id() -> String {
        let signing = payload.canonicalSigningBytes()
        var preimage = Data("SPIDER/TXID/V1\0".utf8)
        preimage.appendUInt32BE(UInt32(signing.count))
        preimage.append(signing)
        preimage.appendString(public_key)
        preimage.appendString(signature)
        return Data(SHA256.hash(data: preimage)).spiderHex
    }

    func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

extension Data {
    fileprivate mutating func appendUInt32BE(_ value: UInt32) {
        append(contentsOf: (0..<4).reversed().map { UInt8(truncatingIfNeeded: value >> (8 * $0)) })
    }
    fileprivate mutating func appendUInt64BE(_ value: UInt64) {
        append(contentsOf: (0..<8).reversed().map { UInt8(truncatingIfNeeded: value >> (8 * $0)) })
    }
    fileprivate mutating func appendString(_ text: String) {
        let bytes = Data(text.utf8)
        precondition(bytes.count <= Int(UInt32.max))
        appendUInt32BE(UInt32(bytes.count))
        append(bytes)
    }
    var spiderHex: String { map { String(format: "%02x", $0) }.joined() }
}

enum SpiderDevnetSigningError: Error {
    case unsupportedNetwork
    case invalidAmount
    case incorrectSender
    case invalidExpiry
}

enum SpiderDevnetSigner {
    static let chainID = "spider-devnet-1"
    static let baseGas: UInt64 = 21_000
    static let defaultGasPrice: UInt64 = 1

    // Bech32m (BIP-350), HRP=spider, payload=first 20 SHA256(pubkey) bytes.
    // This intentionally matches Rust src/address.rs, NOT an Ethereum address.
    static func address(for publicKey: Data) -> String {
        precondition(publicKey.count == 32)
        let digest = Data(SHA256.hash(data: publicKey))
        let payload = Array(digest.prefix(20))
        let converted = convertBits(payload, from: 8, to: 5, pad: true)
        let hrp = "spider"
        let expanded = Array(hrp.utf8).map { $0 >> 5 } + [0] + Array(hrp.utf8).map { $0 & 31 }
        let values = converted + [0, 0, 0, 0, 0, 0]
        let polymodValue = polymod(expanded + values) ^ 0x2bc830a3
        let checksum = (0..<6).map { n in
            UInt8((polymodValue >> (5 * (5 - n))) & 31)
        }
        let alphabet = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l".utf8)
        let tail = (converted + checksum).map { Character(UnicodeScalar(alphabet[Int($0)])) }
        return hrp + "1" + String(tail)
    }

    static func isValidAddress(_ address: String) -> Bool {
        SpiderProtocolV1.isValidAddress(address)
    }

    static func sign(_ transfer: SpiderTransferPayload,
                     privateKey: Curve25519.Signing.PrivateKey) throws -> SpiderSignedTransfer {
        guard transfer.chain_id == chainID else { throw SpiderDevnetSigningError.unsupportedNetwork }
        guard transfer.amount > 0, transfer.gas_limit >= baseGas, transfer.max_fee_per_gas > 0 else {
            throw SpiderDevnetSigningError.invalidAmount
        }
        guard transfer.expiry_height > 0 else { throw SpiderDevnetSigningError.invalidExpiry }
        guard isValidAddress(transfer.sender), isValidAddress(transfer.recipient),
              transfer.asset_id == "SPD" else { throw SpiderDevnetSigningError.unsupportedNetwork }
        let pub = privateKey.publicKey.rawRepresentation
        guard transfer.sender == address(for: pub) else {
            throw SpiderDevnetSigningError.incorrectSender
        }
        let signature = try privateKey.signature(for: transfer.canonicalSigningBytes())
        return SpiderSignedTransfer(payload: transfer, public_key: pub.spiderHex,
                                    signature: signature.spiderHex)
    }

    static func makeSPDTransfer(from sender: String, to recipient: String, amountAtomic: UInt64,
                                nonce: UInt64, certifiedHeight: UInt64,
                                gasPrice: UInt64 = defaultGasPrice) throws -> SpiderTransferPayload {
        let (height, overflow) = certifiedHeight.addingReportingOverflow(50)
        guard !overflow, amountAtomic > 0, gasPrice > 0 else {
            throw SpiderDevnetSigningError.invalidAmount
        }
        return SpiderTransferPayload(chain_id: chainID, sender: sender, recipient: recipient,
                                     asset_id: "SPD", amount: amountAtomic, nonce: nonce,
                                     gas_limit: baseGas, max_fee_per_gas: gasPrice,
                                     expiry_height: height)
    }

    // Non-secret self-test: all values from test-vectors/transfer-v1.json.
    // Can be run from an iOS unit test target after adding this source file.
    static func verifyProtocolFixture() -> Bool {
        let payload = SpiderTransferPayload(
            chain_id: "spider-devnet-1",
            sender: "spider1wkvhwmpssh3lnksdzvr3av954dg062lkx52pfs",
            recipient: "spider1wfzkwgzpyqm6dveelzzvumv3hdxvzca8kf0c4w",
            asset_id: "tUSD", amount: 100_000_000_000, nonce: 0,
            gas_limit: 21_000, max_fee_per_gas: 1, expiry_height: 100)
        let pk = "6e7a1cdd29b0b78fd13af4c5598feff4ef2a97166e3ca6f2e4fbfccd80505bf1"
        let sig = "cb7d652dc42a19418256cfad105c768a1a51156b4d9872e9671e3f6e48b51ac3f2c02435937bef059db91fbd7edc569175eeee56e7a1909a4cd7c62bba9a7f00"
        let value = SpiderSignedTransfer(payload: payload, public_key: pk, signature: sig)
        guard let publicBytes = Data(spiderHex: pk), let signatureBytes = Data(spiderHex: sig),
              let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: publicBytes) else {
            return false
        }
        return address(for: publicBytes) == payload.sender
            && pub.isValidSignature(signatureBytes, for: payload.canonicalSigningBytes())
            && value.id() == "01117f65b9c31ff43af8db25187b7f5f0b18e1fe6ac25ba23215783ef3091468"
    }

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        let generators: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var check: UInt32 = 1
        for v in values {
            let high = check >> 25
            check = ((check & 0x1ffffff) << 5) ^ UInt32(v)
            for n in 0..<5 where ((high >> n) & 1) != 0 {
                check ^= generators[n]
            }
        }
        return check
    }

    private static func convertBits(_ data: [UInt8], from: UInt8, to: UInt8, pad: Bool) -> [UInt8] {
        var accumulator: UInt32 = 0
        var bits = 0
        var result: [UInt8] = []
        let mask = UInt32((1 << to) - 1)
        for byte in data {
            accumulator = ((accumulator << from) | UInt32(byte)) & 0xFFFF
            bits += Int(from)
            while bits >= Int(to) {
                bits -= Int(to)
                result.append(UInt8((accumulator >> bits) & mask))
            }
        }
        if pad && bits > 0 {
            result.append(UInt8((accumulator << (Int(to) - bits)) & mask))
        }
        return result
    }
}

extension Data {
    init?(spiderHex: String) {
        guard spiderHex.count.isMultiple(of: 2) else { return nil }
        var result = Data()
        var index = spiderHex.startIndex
        while index < spiderHex.endIndex {
            let next = spiderHex.index(index, offsetBy: 2)
            guard let value = UInt8(spiderHex[index..<next], radix: 16) else { return nil }
            result.append(value)
            index = next
        }
        self = result
    }
}
