import Foundation

@main struct Stage7DigestDriver {
    static let sender = "0x1111111111111111111111111111111111111111"
    static let recipient = "0x2222222222222222222222222222222222222222"

    private static func encodeBytes(_ bytes: Data) -> Data {
        if bytes.count == 1 && bytes[0] < 0x80 { return bytes }
        if bytes.count <= 55 { return Data([0x80 + UInt8(bytes.count)]) + bytes }
        if bytes.count <= 255 { return Data([0xb8, UInt8(bytes.count)]) + bytes }
        preconditionFailure("Fixture too long")
    }

    private static func encodeList(_ fragments: [Data]) -> Data {
        let content = fragments.reduce(Data(), +)
        if content.count <= 55 { return Data([0xc0 + UInt8(content.count)]) + content }
        if content.count <= 255 { return Data([0xf8, UInt8(content.count)]) + content }
        if content.count <= 65_535 {
            return Data([0xf9, UInt8(content.count >> 8), UInt8(content.count & 0xff)]) + content
        }
        preconditionFailure("Fixture too long")
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func main() throws {
        let tests: [Data] = [Data(), Data([0]), Data("abc".utf8), Data("hello world".utf8),
            Data(repeating: 0xab, count: 135), Data(repeating: 0xab, count: 136),
            Data(repeating: 0xab, count: 137), Data(repeating: 0xab, count: 272),
            Data((0..<2048).map { UInt8($0 % 256) })]
        for (index, data) in tests.enumerated() {
            print("KECCAK_\(index)=\(hex(data)):\(hex(WalletEVMKeccak256.hash(data)))")
        }
        assert(WalletEVMKeccak256.hex(Data()) == "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
        assert(WalletEVMKeccak256.hex(Data("abc".utf8)) == "0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")
        // Critical one-byte 0x81 suffix boundary; independently checked with OpenSSL.
        assert(WalletEVMKeccak256.hex(Data(repeating: 0xab, count: 135)) ==
            "0x932fedc0e854cc4d32eec69e896c7449570052b3aaceacff7b13745325e4cf47")
        let quote = WalletEVMQuote(asset: .usdt, sender: sender, recipient: recipient, amount: "1.25",
            nonce: 7, gasLimit: 90000, maxFeePerGas: 3_000_000_000, priorityFeePerGas: 1_000_000_000,
            maxFeeETH: "0.00027", provider: "fixture", checkedAt: Date())
        let intent = try WalletEVMUnsignedIntent(quote: quote, expectedSender: sender)
        let values = [WalletEVMSigningBytes.quantity(1), WalletEVMSigningBytes.quantity(intent.nonce),
            WalletEVMSigningBytes.quantity(intent.priorityFeePerGas), WalletEVMSigningBytes.quantity(intent.maxFeePerGas),
            WalletEVMSigningBytes.quantity(intent.gasLimit), try WalletEVMSigningBytes.hex(intent.transactionTarget),
            Data(), try WalletEVMSigningBytes.hex(intent.tokenCallData ?? "", maxBytes: 128)]
        let core = values.map(encodeBytes) + [Data([0xc0])]
        let preimage = Data([2]) + encodeList(core)
        let raw = Data([2]) + encodeList(core + [encodeBytes(Data()), encodeBytes(Data([1])), encodeBytes(Data([1]))])
        let result = try WalletEVMSignedEnvelopeGuard.fingerprints(raw: raw, intent: intent)
        assert(result.transactionHash == WalletEVMKeccak256.hex(raw))
        assert(result.signingDigest == WalletEVMKeccak256.hex(preimage))
        assert(result.transactionHash != result.signingDigest)
        print("TX_RAW=\(hex(raw))")
        print("TX_HASH=\(result.transactionHash)")
        print("SIGNING_PREIMAGE=\(hex(preimage))")
        print("SIGNING_DIGEST=\(result.signingDigest)")

        // A signed transaction with swapped recipients must never yield approved fingerprints.
        var mutated = Array(raw)
        let target = Array(try WalletEVMSigningBytes.hex(intent.transactionTarget))
        guard let first = mutated.indices.first(where: { i in
            i + target.count <= mutated.count && Array(mutated[i..<i+target.count]) == target
        }) else { fatalError("fixture target missing") }
        mutated[first] ^= 0x01
        do { _ = try WalletEVMSignedEnvelopeGuard.fingerprints(raw: Data(mutated), intent: intent)
            fatalError("unexpected mismatch approval")
        } catch WalletEVMEnvelopeError.mismatchedIntent { }

        // This is a hash-only check of a published Wallet Core signing fixture.
        let official = "02f8b00180847735940084b2d05e00830130b9946b175474e89094c44da98b954eedeac495271d0f80b844a9059cbb0000000000000000000000005322b34c88ed0691971bf52a7047448f0f4efc840000000000000000000000000000000000000000000000001bc16d674ec80000c080a0adfcfdf98d4ed35a8967a0c1d78b42adb7c5d831cf5a3272654ec8f8bcd7be2ea011641e065684f6aa476f4fd250aa46cd0b44eccdb0a6e1650d658d1998684cdf"
        let bytes = try WalletEVMSigningBytes.hex("0x" + official, maxBytes: 512)
        assert(WalletEVMKeccak256.hex(bytes) == "0x75d9966501dec85f4a0e96ef700a18f40fc634146a78ba549e8beb1f80d00a1a")
        print("Stage 7: Keccak, transaction hashes and intent mismatch vectors passed")
    }
}
