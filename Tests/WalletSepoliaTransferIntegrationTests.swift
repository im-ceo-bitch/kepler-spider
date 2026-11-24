import Foundation
import XCTest
import WalletCore
@testable import Console

/// Public fixture key 1, offline signing only. No live funds, vault or RPC.
final class WalletSepoliaTransferIntegrationTests: XCTestCase {
    func testVerifiedEnvelopeMatchesSignerAndDestination() throws {
        let sender = "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf"
        let recipient = "0x2222222222222222222222222222222222222222"
        let intent = WalletSepoliaIntent(sender: sender, recipient: recipient, amount: "1000000000000000", nonce: 7, gas: 25200, maxFee: 2_000_000_000, priority: 500_000_000, checkedAt: Date())
        var input = try WalletSepoliaSigning.makeInput(intent)
        input.privateKey = Data(repeating: 0, count: 31) + Data([1])
        defer { input.privateKey = Data() }
        let signed: EthereumSigningOutput = AnySigner.sign(input: input, coin: .ethereum)
        XCTAssertEqual(signed.error, .ok)
        XCTAssertEqual(try WalletSepoliaSigning.verify(signed.encoded, intent: intent), WalletEVMKeccak256.hex(signed.encoded))
        let wrongSender = WalletSepoliaIntent(sender: recipient, recipient: recipient, amount: intent.amount, nonce: intent.nonce, gas: intent.gas, maxFee: intent.maxFee, priority: intent.priority, checkedAt: Date())
        XCTAssertThrowsError(try WalletSepoliaSigning.verify(signed.encoded, intent: wrongSender))
        var mainnet = input; mainnet.chainID = Data([1])
        defer { mainnet.privateKey = Data() }
        let wrong: EthereumSigningOutput = AnySigner.sign(input: mainnet, coin: .ethereum)
        XCTAssertThrowsError(try WalletSepoliaSigning.verify(wrong.encoded, intent: intent))
    }
}
