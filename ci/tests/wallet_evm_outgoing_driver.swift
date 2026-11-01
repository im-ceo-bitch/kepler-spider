import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
struct CheckOutgoing {
    static let urls = [URL(string: "https://rpc-a.example")!, URL(string: "https://rpc-b.example")!]
    static let hash = "0x" + String(repeating: "a", count: 64)
    static let blockHash = "0x" + String(repeating: "b", count: 64)
    static let sender = "0x1111111111111111111111111111111111111111"
    static let receiver = "0x2222222222222222222222222222222222222222"

    static func intent(_ asset: WalletEVMAsset = .usdt) throws -> WalletEVMUnsignedIntent {
        try WalletEVMUnsignedIntent(quote: WalletEVMQuote(asset: asset, sender: sender, recipient: receiver,
            amount: asset == .eth ? "0.1" : "1.5", nonce: 7, gasLimit: asset == .eth ? 21000 : 68000,
            maxFeePerGas: 2000000000, priorityFeePerGas: 100000000, maxFeeETH: "0.001",
            provider: "rpc-a", checkedAt: Date()), expectedSender: sender)
    }
    static func tx(_ intent: WalletEVMUnsignedIntent, chain: String = "0x1", from: String = sender,
                   nonce: String = "0x7", input: String? = nil) -> [String: Any] {
        let ethValue = try! WalletEVMUnits.hexFromDecimal(intent.asset == .eth ? intent.baseUnits : "0")
        return ["hash": hash, "from": from, "to": intent.transactionTarget, "type": "0x2",
                "chainId": chain, "nonce": nonce, "gas": "0x" + String(intent.gasLimit, radix: 16),
                "maxFeePerGas": "0x" + String(intent.maxFeePerGas, radix: 16),
                "maxPriorityFeePerGas": "0x" + String(intent.priorityFeePerGas, radix: 16),
                "value": ethValue, "input": input ?? (intent.tokenCallData ?? "0x"),
                "blockHash": blockHash, "blockNumber": "0x64"]
    }
    static func receipt(_ intent: WalletEVMUnsignedIntent, status: String = "0x1", logContract: String? = nil,
                        logRecipient: String = receiver) -> [String: Any] {
        let topic = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
        let fromTopic = "0x" + String(repeating: "0", count: 24) + String(sender.dropFirst(2))
        let toTopic = "0x" + String(repeating: "0", count: 24) + String(logRecipient.dropFirst(2))
        let tokenData = "0x" + String(repeating: "0", count: 58) + "16e360"
        let logs: [[String: Any]] = intent.asset == .eth ? [] : [
            ["address": logContract ?? intent.transactionTarget, "topics": [topic, fromTopic, toTopic],
             "data": tokenData, "transactionHash": hash, "removed": false]
        ]
        return ["transactionHash": hash, "from": sender, "to": intent.transactionTarget,
                "status": status, "blockNumber": "0x64", "blockHash": blockHash, "logs": logs]
    }
    static func mock(_ intent: WalletEVMUnsignedIntent, txData: [String: Any]? = nil,
                     receiptData: [String: Any]? = nil, chain: String = "0x1", head: String = "0x70",
                     block: String = blockHash, noTx: Bool = false,
                     mutator: ((URL, String, Any?) -> Any?)? = nil) -> WalletEVMOutgoingTracker.Transport {
        { url, method, _ in
            let result: Any?
            switch method {
            case "eth_chainId": result = chain
            case "eth_getTransactionByHash": result = noTx ? nil : (txData ?? tx(intent))
            case "eth_getTransactionReceipt": result = receiptData ?? receipt(intent)
            case "eth_getBlockByNumber": result = ["hash": block]
            case "eth_blockNumber": result = head
            default: result = nil
            }
            let modified = mutator?(url, method, result) ?? result
            return modified is NSNull ? nil : modified
        }
    }
    static func tracker(_ rpc: @escaping WalletEVMOutgoingTracker.Transport, urls endpoints: [URL] = urls) -> WalletEVMOutgoingTracker {
        WalletEVMOutgoingTracker(endpoints: endpoints, transport: rpc)
    }
    static func assert(_ condition: @autoclosure () -> Bool, _ msg: String) {
        guard condition() else { fatalError(msg) }
    }
    static func expect(_ expected: WalletEVMOutgoingError, _ body: () async throws -> WalletEVMOutgoingAssessment) async {
        do { _ = try await body(); fatalError("expected \(expected)") }
        catch let error as WalletEVMOutgoingError { assert(error == expected, "error \(error) expected \(expected)") }
        catch { fatalError("unexpected \(error)") }
    }
    static func main() async throws {
        let usdt = try intent()
        let success = try await tracker(mock(usdt)).reconcile(txHash: hash, intent: usdt)
        if case .confirmed(let info) = success {
            assert(info.confirmations == 13 && info.asset == .usdt && info.amountBaseUnits == "1500000", "USDT success")
        } else { fatalError("two matching RPCs + 13 confirmations required") }

        let one = try await tracker(mock(usdt), urls: [urls[0]]).reconcile(txHash: hash, intent: usdt)
        if case .observed(let info, providers: 1) = one { assert(info.confirmations == 13, "one observation") }
        else { fatalError("one RPC must not confirm") }
        let duplicateEndpoint = try await tracker(mock(usdt), urls: [urls[0], urls[0]]).reconcile(txHash: hash, intent: usdt)
        if case .observed(_, providers: 1) = duplicateEndpoint {} else { fatalError("duplicate RPC host cannot count twice") }
        let early = try await tracker(mock(usdt, head: "0x65")).reconcile(txHash: hash, intent: usdt)
        if case .observed(let e, providers: 2) = early { assert(e.confirmations == 2, "early status") }
        else { fatalError("early tx must not confirm") }
        let none = try await tracker(mock(usdt, noTx: true)).reconcile(txHash: hash, intent: usdt)
        if case .notSeen = none {} else { fatalError("not found") }
        let pending = try await tracker(mock(usdt, mutator: { _, m, result in
            m == "eth_getTransactionReceipt" ? NSNull() : result
        })).reconcile(txHash: hash, intent: usdt)
        if case .pending(providers: 2) = pending {} else { fatalError("pending must stay pending") }
        await expect(.invalidHash) { try await tracker(mock(usdt)).reconcile(txHash: "0x33", intent: usdt) }
        await expect(.inconsistentProviders) { try await tracker(mock(usdt, chain: "0x89")).reconcile(txHash: hash, intent: usdt) }
        await expect(.inconsistentProviders) { try await tracker(mock(usdt, txData: tx(usdt, from: receiver))).reconcile(txHash: hash, intent: usdt) }
        await expect(.inconsistentProviders) { try await tracker(mock(usdt, txData: tx(usdt, nonce: "0x8"))).reconcile(txHash: hash, intent: usdt) }
        await expect(.inconsistentProviders) { try await tracker(mock(usdt, txData: tx(usdt, input: "0x"))).reconcile(txHash: hash, intent: usdt) }
        await expect(.inconsistentProviders) { try await tracker(mock(usdt, receiptData: receipt(usdt, logRecipient: sender))).reconcile(txHash: hash, intent: usdt) }
        await expect(.inconsistentProviders) { try await tracker(mock(usdt, receiptData: receipt(usdt, logContract: WalletEVMAsset.usdc.contract!))).reconcile(txHash: hash, intent: usdt) }
        await expect(.inconsistentProviders) { try await tracker(mock(usdt, block: "0x" + String(repeating: "f", count: 64))).reconcile(txHash: hash, intent: usdt) }
        let revert = try await tracker(mock(usdt, receiptData: receipt(usdt, status: "0x0"))).reconcile(txHash: hash, intent: usdt)
        if case .reverted(let e) = revert { assert(!e.succeeded, "revert") }
        else { fatalError("revert must not appear as success") }
        let eth = try intent(.eth)
        let native = try await tracker(mock(eth)).reconcile(txHash: hash, intent: eth)
        if case .confirmed(let e) = native { assert(e.asset == .eth, "ETH confirmation") }
        else { fatalError("native ETH success") }
        let mixed = tracker(mock(usdt, mutator: { url, method, result in
            if url == urls[1] && method == "eth_getBlockByNumber" { return ["hash": "0x" + String(repeating: "f", count: 64)] }
            return result
        }))
        await expect(.inconsistentProviders) { try await mixed.reconcile(txHash: hash, intent: usdt) }
        print("WalletEVMOutgoingTracker: 17 core scenarios passed")
    }
}
