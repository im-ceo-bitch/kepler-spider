import Foundation
import XCTest
import WalletCore
@testable import Console

/// Runs on macOS Xcode / GitHub build-only CI, not in Linux Swift tests.
final class WalletEVMSigningTests: XCTestCase {
    func testEIP1559SignerMatchesOfficialWalletCoreVector() throws {
        // Official published Wallet Core test fixture, NOT a user's private key.
        let input = EthereumSigningInput.with {
            $0.chainID = Data([1])
            $0.nonce = Data()
            $0.txMode = .enveloped
            $0.gasLimit = Data([0x01, 0x30, 0xb9])
            $0.maxInclusionFeePerGas = Data([0x77, 0x35, 0x94, 0x00])
            $0.maxFeePerGas = Data([0xb2, 0xd0, 0x5e, 0x00])
            $0.toAddress = "0x6b175474e89094c44da98b954eedeac495271d0f"
            $0.privateKey = Data([0x60,0x8d,0xcb,0x17,0x42,0xbb,0x3f,0xb7,0xae,0xc0,0x02,0x07,0x4e,0x34,0x20,0xe4,0xfa,0xb7,0xd0,0x0c,0xce,0xd7,0x9c,0xcd,0xac,0x53,0xed,0x5b,0x27,0x13,0x81,0x51])
            $0.transaction = EthereumTransaction.with {
                $0.erc20Transfer = EthereumTransaction.ERC20Transfer.with {
                    $0.to = "0x5322b34c88ed0691971bf52a7047448f0f4efc84"
                    $0.amount = Data([0x1b,0xc1,0x6d,0x67,0x4e,0xc8,0x00,0x00])
                }
            }
        }
        let output: EthereumSigningOutput = AnySigner.sign(input: input, coin: .ethereum)
        let expected = "02f8b00180847735940084b2d05e00830130b9946b175474e89094c44da98b954eedeac495271d0f80b844a9059cbb0000000000000000000000005322b34c88ed0691971bf52a7047448f0f4efc840000000000000000000000000000000000000000000000001bc16d674ec80000c080a0adfcfdf98d4ed35a8967a0c1d78b42adb7c5d831cf5a3272654ec8f8bcd7be2ea011641e065684f6aa476f4fd250aa46cd0b44eccdb0a6e1650d658d1998684cdf"
        XCTAssertEqual(output.encoded.map { String(format: "%02x", $0) }.joined(), expected)
    }

    func testMainnetIntentProducesEnvelopedTransactionWithCorrectContract() throws {
        let now = Date()
        let sender = "0x1111111111111111111111111111111111111111"
        let recipient = "0x2222222222222222222222222222222222222222"
        let quote = WalletEVMQuote(asset: .usdc, sender: sender, recipient: recipient, amount: "1.25",
            nonce: 8, gasLimit: 70_000, maxFeePerGas: 3_000_000_000,
            priorityFeePerGas: 1_000_000_000, maxFeeETH: "0.00021", provider: "fixture", checkedAt: now)
        let intent = try WalletEVMUnsignedIntent(quote: quote, expectedSender: sender)
        let signingInput = try WalletEVMOfflineSigner.makeInput(intent: intent)
        XCTAssertEqual(signingInput.chainID, Data([1]))
        XCTAssertEqual(signingInput.nonce, Data([8]))
        XCTAssertEqual(signingInput.toAddress, WalletEVMAsset.usdc.contract)
        XCTAssertEqual(signingInput.gasLimit, WalletEVMSigningBytes.quantity(70_000))
        XCTAssertEqual(signingInput.maxFeePerGas, WalletEVMSigningBytes.quantity(3_000_000_000))
        XCTAssertEqual(signingInput.privateKey, Data())
        XCTAssertEqual(signingInput.transaction.erc20Transfer.to, recipient)
        XCTAssertEqual(signingInput.transaction.erc20Transfer.amount, try WalletEVMSigningBytes.decimal("1250000"))
    }
}
