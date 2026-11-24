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
        rejected("signed RPC quantity") { _ = try WalletEVMUnits.integer("0x+1", upperBound: 100) }
        rejected("noncanonical RPC quantity") { _ = try WalletEVMUnits.integer("0x01", upperBound: 100) }
        rejected("malformed balance") { _ = try WalletEVMUnits.decimalFromHex("0x０") }
        rejected("malformed decimal") { _ = try WalletEVMUnits.decimal("12garbage") }
        rejected("zero recipient") { _ = try WalletEVMUnits.transferData(to: "0x" + String(repeating: "0", count: 40), baseUnits: "1") }
        assert(!WalletEVMUnits.isAddress(recipient + "\n"))
        let future = WalletEVMQuote(asset: .eth, sender: quote.sender, recipient: quote.recipient,
            amount: quote.amount, nonce: quote.nonce, gasLimit: quote.gasLimit, maxFeePerGas: quote.maxFeePerGas,
            priorityFeePerGas: quote.priorityFeePerGas, maxFeeETH: quote.maxFeeETH, provider: quote.provider,
            checkedAt: Date().addingTimeInterval(60))
        assert(!future.matches(sender: future.sender, recipient: future.recipient, amount: future.amount, asset: .eth))
        eq(try WalletEVMUnits.hasBalance("0x" + String(repeating: "f", count: 64), required: "1", abiWord: true), true, "full uint256 balance")
        eq(try WalletEVMUnits.hasBalance("0xff", required: "256", abiWord: false), false, "exact low balance")
        eq(try WalletEVMUnits.hasBalance("0x100", required: "256", abiWord: false), true, "exact equality")
        rejected("over uint256") { _ = try WalletEVMUnits.hexFromDecimal(String(repeating: "9", count: 78)) }
        rejected("padded native quantity") { _ = try WalletEVMUnits.hasBalance("0x01", required: "1", abiWord: false) }
        rejected("short token word") { _ = try WalletEVMUnits.hasBalance("0x1", required: "1", abiWord: true) }
        try WalletEVMUnits.validateSimulation("0x", asset: .usdt)
        rejected("empty USDC return") { try WalletEVMUnits.validateSimulation("0x", asset: .usdc) }
        rejected("false USDT return") { try WalletEVMUnits.validateSimulation("0x" + String(repeating: "0", count: 64), asset: .usdt) }
        let endpoint = URL(string: "https://rpc.example")!
        assert(WalletEVMNoRedirect.matches(URL(string: "https://rpc.example/"), endpoint))
        assert(!WalletEVMNoRedirect.matches(URL(string: "http://rpc.example/"), endpoint))
        assert(!WalletEVMNoRedirect.matches(URL(string: "https://other.example/"), endpoint))
        assert(!WalletEVMNoRedirect.matches(URL(string: "https://rpc.example:444/"), endpoint))
        assert(!WalletEVMNoRedirect.matches(URL(string: "https://rpc.example/other"), endpoint))
        print("PASS WalletEVMPreflight: extended scenarios")
    }
}
