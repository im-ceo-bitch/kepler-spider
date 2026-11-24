import Foundation

@main struct Driver {
    static let owner = "0x1111111111111111111111111111111111111111"
    static let recipient = "0x2222222222222222222222222222222222222222"
    static let trueWord = "0x" + String(repeating: "0", count: 63) + "1"
    static func word(_ value: String) -> String { "0x" + String(repeating: "0", count: 64 - value.count) + value }
    static func check(_ result: Bool) { precondition(result) }
    static func fail(_ work: () throws -> Void) { do { try work(); fatalError("expected rejection") } catch {} }
    static func failAsync(_ work: () async throws -> Void) async { do { try await work(); fatalError("expected rejection") } catch {} }
    static func mock(network: WalletEVMNetwork, token: WalletNetworkAsset, tokenBalance: String = word("f4240"), native: String = "0xde0b6b3a7640000", simulation: String = trueWord, wrongChain: Bool = false, gas: String = "0x5208", price: String = "0x3b9aca00") -> WalletNetworkRPCClient {
        .init { endpoint, method, bytes in
            precondition(network.endpoints.contains(endpoint))
            let params = try JSONSerialization.jsonObject(with: bytes) as! [Any]
            switch method {
            case "eth_chainId": return wrongChain ? "0x2" : "0x" + String(network.id, radix: 16)
            case "eth_getBalance": precondition(params[0] as? String == owner); return native
            case "eth_call":
                let call = params[0] as! [String:String]
                if call["data"]?.hasPrefix("0x70a08231") == true {
                    precondition(call["to"] == token.contract && call["data"] == "0x70a08231" + String(repeating: "0", count: 24) + owner.dropFirst(2)); return tokenBalance
                }
                precondition(params[1] as? String == "pending" && call["from"] == owner && call["gas"] != nil && call["gasPrice"] != nil)
                return simulation
            case "eth_estimateGas":
                let call = params[0] as! [String:String]
                precondition(call["from"] == owner)
                if token.isNative { precondition(call["to"] == recipient && call["value"] != "0x0" && call["data"] == nil) }
                else { precondition(call["to"] == token.contract && call["value"] == "0x0" && call["data"]?.hasPrefix("0xa9059cbb") == true) }
                return gas
            case "eth_gasPrice": return price
            case "eth_getTransactionCount": precondition(params[0] as? String == owner && params[1] as? String == "pending"); return "0x7"
            default: fatalError("unexpected RPC")
            }
        }
    }
    static func main() async throws {
        precondition(WalletNetworkAsset.quoteAssets.count == 12)
        precondition(Set(WalletNetworkAsset.quoteAssets.map(\.id)).count == 12)
        for token in WalletNetworkAsset.tokens { precondition(WalletNetworkReader.validAddress(token.contract) && token.decimals == 6) }
        precondition(!WalletNetworkReader.validAddress(owner + "\n"))
        check(try WalletExactAmount.add("999", "1") == "1000")
        check(try WalletExactAmount.multiply("999", by: 1000) == "999000")
        check(try WalletExactAmount.multiply("10", by: 0) == "0")
        fail { _ = try WalletExactAmount.add(WalletExactAmount.max, "1") }
        fail { _ = try WalletExactAmount.multiply(WalletExactAmount.max, by: 2) }
        check(try WalletExactAmount.abiWord(word("0")) == "0")
        check(try WalletExactAmount.abiWord("0x" + String(repeating: "f", count: 64)) == WalletExactAmount.max)
        for invalid in ["0x1", "0x", "0x" + String(repeating: "g", count: 64), "0x" + String(repeating: "0", count: 65)] { fail { _ = try WalletExactAmount.abiWord(invalid) } }
        for token in WalletNetworkAsset.tokens {
            let snap = try await mock(network: token.network, token: token).snapshot(token, owner: owner)
            precondition(snap.raw == "1000000" && snap.amount == "1" && snap.matches(asset: token, owner: owner))
            let quote = try await WalletNetworkTransferPreview.fetch(asset: token, sender: owner, recipient: recipient, amount: "1", client: mock(network: token.network, token: token))
            precondition(quote.rawAmount == "1000000" && quote.gas == 25200 && quote.nonce == 7 && quote.estimatedFee == "25200000000000" && quote.isFresh())
            precondition(!quote.isFresh(now: quote.checkedAt.addingTimeInterval(45)))
        }
        for network in WalletEVMNetwork.allCases {
            let asset = WalletNetworkAsset.native(network)
            let quote = try await WalletNetworkTransferPreview.fetch(asset: asset, sender: owner, recipient: recipient, amount: "0.1", client: mock(network: network, token: asset, simulation: "0x"))
            precondition(quote.rawAmount == "100000000000000000" && quote.asset.network == network)
        }
        let token = WalletNetworkAsset.ethereumUSDC
        for client in [mock(network: .ethereum, token: token, tokenBalance: "0x1"), mock(network: .ethereum, token: token, tokenBalance: word("0")), mock(network: .ethereum, token: token, native: "0x1"), mock(network: .ethereum, token: token, simulation: word("0")), mock(network: .ethereum, token: token, simulation: "0x"), mock(network: .ethereum, token: token, wrongChain: true), mock(network: .ethereum, token: token, gas: "0x1"), mock(network: .ethereum, token: token, price: "0x0")] {
            await failAsync { _ = try await WalletNetworkTransferPreview.fetch(asset: token, sender: owner, recipient: recipient, amount: "1", client: client) }
        }
        await failAsync { _ = try await WalletNetworkTransferPreview.fetch(asset: token, sender: owner, recipient: owner, amount: "1", client: mock(network: .ethereum, token: token)) }
        let native = WalletNetworkAsset.native(.ethereum)
        await failAsync { _ = try await WalletNetworkTransferPreview.fetch(asset: native, sender: owner, recipient: recipient, amount: "1", client: mock(network: .ethereum, token: native, simulation: "0x")) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = WalletTokenSnapshot(asset: token, owner: owner, raw: "1000000", fetchedAt: now)
        let price = WalletNetworkPrice(usd: 1, updatedAt: now)
        let route = try WalletRouteRequest(source: token, destination: native, owner: owner, amount: "1")
        try route.checkFunding(snap, now: now)
        fail { try route.checkFunding(snap, now: now.addingTimeInterval(46)) }
        fail { try route.checkFunding(.init(asset: token, owner: recipient, raw: "1000000", fetchedAt: now), now: now) }
        fail { try route.checkFunding(.init(asset: token, owner: owner, raw: "999999", fetchedAt: now), now: now) }
        fail { try route.checkFunding(.init(asset: native, owner: owner, raw: "1000000", fetchedAt: now), now: now) }
        let v = WalletAssetPortfolio.calculate(owner: owner, snapshots: [token.id: snap], prices: ["usd-coin": price], now: now)
        precondition(v.usd == 1 && v.valued == 1 && v.total == 12 && v.partial)
        precondition(WalletAssetPortfolio.calculate(owner: recipient, snapshots: [token.id: snap], prices: ["usd-coin": price], now: now).usd == nil)
        precondition(WalletAssetPortfolio.calculate(owner: owner, snapshots: [token.id: snap], prices: ["usd-coin": price], now: now.addingTimeInterval(301)).usd == nil)
        precondition(WalletAssetPortfolio.calculate(owner: owner, snapshots: [token.id: snap], prices: ["usd-coin": price], assets: [token,token], now: now).usd == 1)
        let decoded = try WalletNetworkMarket.decode(Data("{\"usd-coin\":{\"usd\":0.98,\"last_updated_at\":1700000000},\"tether\":{\"usd\":1.01,\"last_updated_at\":1700000000}}".utf8), now: now)
        precondition(decoded.count == 2)
        print("PASS token engine: balances, exact units, 12 assets, six networks, simulation, route funding and account isolation")
    }
}
