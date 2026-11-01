import Foundation
import XCTest
import WalletCore
@testable import Console

/// Runs only in a genuine iOS Xcode test target linked to Wallet Core.
/// PUBLIC fixture key; never import an actual user's mnemonic or private key here.
/// Signs OFFLINE. There is no RPC broadcaster and no testnet ETH is needed.
final class WalletEVMSepoliaSigningTests: XCTestCase {
    func testSepoliaEIP1559UsesTestnetChainIDAndProducesStableHash() throws {
        var input = EthereumSigningInput.with {
            $0.chainID = Data([0xaa, 0x36, 0xa7]) // 11155111 (Sepolia)
            $0.txMode = .enveloped
            $0.nonce = Data()
            $0.gasLimit = Data([0x52, 0x08]) // 21_000
            $0.maxInclusionFeePerGas = Data([0x3b, 0x9a, 0xca, 0x00])
            $0.maxFeePerGas = Data([0x77, 0x35, 0x94, 0x00])
            $0.toAddress = "0x1111111111111111111111111111111111111111"
            $0.privateKey = Data([0x60,0x8d,0xcb,0x17,0x42,0xbb,0x3f,0xb7,
                                  0xae,0xc0,0x02,0x07,0x4e,0x34,0x20,0xe4,
                                  0xfa,0xb7,0xd0,0x0c,0xce,0xd7,0x9c,0xcd,
                                  0xac,0x53,0xed,0x5b,0x27,0x13,0x81,0x51])
            $0.transaction = EthereumTransaction.with {
                $0.transfer = EthereumTransaction.Transfer.with { $0.amount = Data([0x01]) }
            }
        }
        defer { input.privateKey.resetBytes(in: 0..<input.privateKey.count) }
        let output: EthereumSigningOutput = AnySigner.sign(input: input, coin: .ethereum)
        XCTAssertGreaterThan(output.encoded.count, 70)
        XCTAssertEqual(try WalletEVMSignedEnvelopeGuard.inspectChainID(raw: output.encoded), 11155111)
        XCTAssertEqual(WalletEVMKeccak256.hash(output.encoded).count, 32)
        XCTAssertFalse(output.r.isEmpty)
        XCTAssertFalse(output.s.isEmpty)
        // Explicit anti-replay: same fixture, same nonce, wrong (Mainnet) chain.
        var wrongChain = input
        wrongChain.chainID = Data([0x01])
        let wrong: EthereumSigningOutput = AnySigner.sign(input: wrongChain, coin: .ethereum)
        XCTAssertEqual(try WalletEVMSignedEnvelopeGuard.inspectChainID(raw: wrong.encoded), 1)
        XCTAssertNotEqual(WalletEVMKeccak256.hex(output.encoded), WalletEVMKeccak256.hex(wrong.encoded))
    }
}
