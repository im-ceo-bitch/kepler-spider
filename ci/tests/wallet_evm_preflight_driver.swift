import Foundation

@main
struct Validate {
    static func main() throws {
        func eq<T: Equatable>(_ got: T, _ expected: T, _ context: String) {
            guard got == expected else { fatalError("\(context) expected \(expected), got \(got)") }
        }
        func rejected(_ context: String, _ test: () throws -> Void) {
            do { try test(); fatalError("Accepted invalid input \(context)") }
            catch is WalletEVMPreflightError { }
            catch { fatalError("Unexpected error \(context): \(error)") }
        }
        eq(try WalletEVMUnits.baseUnits("1", decimals: 18), "1000000000000000000", "1 ETH")
        eq(try WalletEVMUnits.baseUnits("0.000000000000000001", decimals: 18), "1", "wei")
        eq(try WalletEVMUnits.baseUnits("0,25", decimals: 6), "250000", "USDT amount")
        eq(try WalletEVMUnits.baseUnits("0001.01", decimals: 6), "1010000", "leading zero")
        eq(try WalletEVMUnits.baseUnits("0.000001", decimals: 6), "1", "minimum USDC")
        rejected("zero") { _ = try WalletEVMUnits.baseUnits("0", decimals: 18) }
        rejected("scientific notation") { _ = try WalletEVMUnits.baseUnits("1e19", decimals: 18) }
        rejected("negative") { _ = try WalletEVMUnits.baseUnits("-1", decimals: 18) }
        rejected("overprecision") { _ = try WalletEVMUnits.baseUnits("0.0000001", decimals: 6) }
        rejected("too many digits") { _ = try WalletEVMUnits.baseUnits("1234567890123", decimals: 18) }
        eq(try WalletEVMUnits.hexFromDecimal("1000000000000000000"), "0xde0b6b3a7640000", "wei hex")
        eq(try WalletEVMUnits.hexFromDecimal("0"), "0x0", "zero hex")
        eq(try WalletEVMUnits.integer("0x5208", upperBound: 100_000), 21_000, "gas")
        rejected("invalid hex") { _ = try WalletEVMUnits.integer("0xzz", upperBound: 100_000) }
        rejected("gas upper bound") { _ = try WalletEVMUnits.integer("0xf4241", upperBound: 1_000_000) }
        eq(try WalletEVMUnits.decimalFromHex("0x" + String(repeating: "0", count: 62) + "ff"), Decimal(255), "padded ABI balance")
        rejected("excessive ABI") { _ = try WalletEVMUnits.decimalFromHex("0x" + String(repeating: "f", count: 64)) }
        let recipient = "0x1111111111111111111111111111111111111111"
        eq(try WalletEVMUnits.transferData(to: recipient, baseUnits: "1000000"),
           "0xa9059cbb" + String(repeating: "0", count: 24) + String(repeating: "1", count: 40) +
           String(repeating: "0", count: 59) + "f4240", "ABI ERC20 transfer")
        rejected("recipient") { _ = try WalletEVMUnits.transferData(to: "abc", baseUnits: "1") }
        let quote = WalletEVMQuote(asset: .eth, sender: recipient, recipient: "0x2222222222222222222222222222222222222222",
                                   amount: "1", nonce: 1, gasLimit: 25200, maxFeePerGas: 2000000000,
                                   priorityFeePerGas: 1000000000, maxFeeETH: "0.0000504", provider: "rpc", checkedAt: Date())
        assert(quote.matches(sender: recipient, recipient: quote.recipient, amount: "1", asset: .eth))
        assert(!quote.matches(sender: recipient, recipient: quote.recipient, amount: "2", asset: .eth))
        print("PASS WalletEVMPreflight: 21 scenarios")
    }
}
