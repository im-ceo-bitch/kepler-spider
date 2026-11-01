import Foundation

@main
struct WalletEVMSigningStage2Driver {
    static func main() throws {
        let a = "0x1111111111111111111111111111111111111111"
        let b = "0x2222222222222222222222222222222222222222"
        let now = Date()
        func quote(_ asset: WalletEVMAsset = .eth, _ amount: String = "0.5", at: Date = now) -> WalletEVMQuote {
            WalletEVMQuote(asset: asset, sender: a, recipient: b, amount: amount, nonce: 9, gasLimit: asset == .eth ? 25_200 : 90_000,
                maxFeePerGas: 3_000_000_000, priorityFeePerGas: 1_000_000_000,
                maxFeeETH: "0.0000756", provider: "test.rpc", checkedAt: at)
        }
        func rejects(_ label: String, _ block: () throws -> Void) {
            do { try block(); fatalError("accepted invalid: \(label)") }
            catch is WalletEVMSigningError { }
            catch is WalletEVMPreflightError { }
            catch { fatalError("unexpected: \(label) \(error)") }
        }
        let eth = try WalletEVMUnsignedIntent(quote: quote(), expectedSender: a, now: now)
        assert(eth.baseUnits == "500000000000000000")
        assert(eth.transactionTarget == b && eth.tokenCallData == nil)
        let actualEth = try WalletEVMSigningBytes.decimal(eth.baseUnits)
        let referenceEth = try WalletEVMSigningBytes.hex("0x06f05b59d3b20000")
        assert(actualEth == referenceEth)
        assert(WalletEVMSigningBytes.quantity(0) == Data())
        assert(WalletEVMSigningBytes.quantity(0x1234) == Data([0x12, 0x34]))
        assert(WalletEVMSigningBytes.quantity(UInt64.max) == Data(repeating: 0xff, count: 8))
        let oneNibble = try WalletEVMSigningBytes.hex("0x0")
        assert(oneNibble == Data([0x00]))
        let oddHex = try WalletEVMSigningBytes.hex("0xabc")
        assert(oddHex == Data([0x0a, 0xbc]))
        let token = try WalletEVMUnsignedIntent(quote: quote(.usdt, "1.25"), expectedSender: a, now: now)
        assert(token.baseUnits == "1250000" && token.transactionTarget == WalletEVMAsset.usdt.contract)
        assert(token.tokenCallData?.hasPrefix("0xa9059cbb") == true)
        assert(token.tokenCallData?.count == 138)
        let encodedCall = try WalletEVMSigningBytes.hex(token.tokenCallData!, maxBytes: 128)
        assert(encodedCall.count == 68)
        rejects("wrong wallet") { _ = try WalletEVMUnsignedIntent(quote: quote(), expectedSender: b, now: now) }
        rejects("expired") { _ = try WalletEVMUnsignedIntent(quote: quote(at: now.addingTimeInterval(-46)), expectedSender: a, now: now) }
        rejects("future") { _ = try WalletEVMUnsignedIntent(quote: quote(at: now.addingTimeInterval(10)), expectedSender: a, now: now) }
        rejects("overprecision") { _ = try WalletEVMUnsignedIntent(quote: quote(.usdt,"0.0000001"), expectedSender: a, now: now) }
        rejects("self send") {
            let bad = WalletEVMQuote(asset: .eth, sender: a, recipient: a, amount: "1", nonce: 1, gasLimit: 25200,
                maxFeePerGas: 2_000_000_000, priorityFeePerGas: 1_000_000_000,
                maxFeeETH: "0.0001", provider: "test", checkedAt: now)
            _ = try WalletEVMUnsignedIntent(quote: bad, expectedSender: a, now: now)
        }
        rejects("zero gas") {
            let bad = WalletEVMQuote(asset: .eth, sender: a, recipient: b, amount: "1", nonce: 1, gasLimit: 0,
                maxFeePerGas: 2_000_000_000, priorityFeePerGas: 1_000_000_000,
                maxFeeETH: "0.0001", provider: "test", checkedAt: now)
            _ = try WalletEVMUnsignedIntent(quote: bad, expectedSender: a, now: now)
        }
        rejects("fee inverted") {
            let bad = WalletEVMQuote(asset: .eth, sender: a, recipient: b, amount: "1", nonce: 1, gasLimit: 25200,
                maxFeePerGas: 1_000_000, priorityFeePerGas: 2_000_000,
                maxFeeETH: "0.0001", provider: "test", checkedAt: now)
            _ = try WalletEVMUnsignedIntent(quote: bad, expectedSender: a, now: now)
        }
        rejects("invalid hex") { _ = try WalletEVMSigningBytes.hex("0xgh") }
        rejects("oversized hex") { _ = try WalletEVMSigningBytes.hex("0x" + String(repeating: "a", count: 66)) }
        print("PASS EVM stage 2 unsigned intent: 19 assertions")
    }
}
