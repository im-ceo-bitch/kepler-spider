import Foundation

@main struct Driver {
    static let owner = "0x1111111111111111111111111111111111111111"
    static func expectFailure(_ f: () throws -> Void) { do { try f(); fatalError("Expected failure") } catch {} }
    static func check(_ result: Bool) { precondition(result) }
    static func json(_ r: WalletRouteRequest, changes: [String: Any] = [:], estimate: [String: Any] = [:]) throws -> Data {
        func token(_ a: WalletNetworkAsset) -> [String: Any] { ["address": a.contract, "chainId": a.network.id, "decimals": a.decimals] }
        var action: [String: Any] = ["fromChainId": r.source.network.id, "toChainId": r.destination.network.id, "fromToken": token(r.source), "toToken": token(r.destination), "fromAddress": r.owner, "toAddress": r.owner, "fromAmount": r.rawAmount, "slippage": 0.005]
        action.merge(changes) { _, new in new }
        var e: [String: Any] = ["fromAmount": r.rawAmount, "toAmount": "1000", "toAmountMin": "990", "executionDuration": 120]
        e.merge(estimate) { _, new in new }
        return try JSONSerialization.data(withJSONObject: ["tool": "test_route", "action": action, "estimate": e, "transactionRequest": ["data": "untrusted"]])
    }
    static func main() async throws {
        check(try WalletExactAmount.fromHex("0x" + String(repeating: "f", count: 64)) == WalletExactAmount.max)
        check(try WalletExactAmount.fromHex("0x0") == "0")
        check(try WalletExactAmount.parse("0.000000000000000001", decimals: 18) == "1")
        check(WalletExactAmount.display("1", decimals: 18) == "0.000000000000000001")
        check(WalletExactAmount.display("123400", decimals: 4) == "12.34")
        for bad in ["0x", "0x00", "0x-1", "0xgg", "0x" + String(repeating: "f", count: 65)] { expectFailure { _ = try WalletExactAmount.fromHex(bad) } }
        for bad in ["1e5", "-1", "1,2", " 1", "1.", "1.0000001", "１２"] { expectFailure { _ = try WalletExactAmount.parse(bad, decimals: 6) } }
        check(!WalletExactAmount.valid(WalletExactAmount.max + "0"))
        let reader = WalletNetworkReader { endpoint, method, params in
            if method == "eth_chainId" { return endpoint.contains("arbitrum.io") ? "0x1" : "0xa4b1" }
            precondition(method == "eth_getBalance" && params == [owner, "latest"] && !endpoint.contains("arbitrum.io")); return "0x1"
        }
        let balance = try await reader.balance(network: .arbitrum, address: owner)
        check(balance.raw == "1" && balance.network == .arbitrum)
        do { _ = try await WalletNetworkReader { _, method, _ in precondition(method == "eth_chainId"); return "0x1" }.balance(network: .base, address: owner); fatalError("wrong chain accepted") } catch {}
        let r = try WalletRouteRequest(source: .native(.ethereum), destination: .ethereumUSDC, owner: owner, amount: "0.01")
        let q = try WalletRoutePreview.decode(json(r), request: r)
        check(q.expected == "1000" && q.minimum == "990" && q.isFresh())
        check(!q.isFresh(now: q.receivedAt.addingTimeInterval(45)))
        check(!q.isFresh(now: q.receivedAt.addingTimeInterval(-1)))
        let params = URLComponents(url: try r.url(), resolvingAgainstBaseURL: false)!.queryItems!
        check(params.first(where: { $0.name == "slippage" })?.value == "0.0050")
        for mutation: [String: Any] in [["fromChainId": 8453], ["toChainId": 56], ["toAddress": "0x2222222222222222222222222222222222222222"], ["fromAmount": "1"], ["slippage": 0.1], ["toToken": ["address": r.destination.contract, "chainId": 1, "decimals": 18]]] {
            expectFailure { _ = try WalletRoutePreview.decode(json(r, changes: mutation), request: r) }
        }
        for mutation: [String: Any] in [["toAmountMin": "1001"], ["toAmountMin": "0"], ["toAmount": "1e9"], ["fromAmount": "0"], ["executionDuration": -1]] {
            expectFailure { _ = try WalletRoutePreview.decode(json(r, estimate: mutation), request: r) }
        }
        let bridge = try WalletRouteRequest(source: .native(.ethereum), destination: .native(.base), owner: owner, amount: "0.1")
        check(try WalletRoutePreview.decode(json(bridge), request: bridge).request.destination.network == .base)
        expectFailure { _ = try WalletRouteRequest(source: .native(.base), destination: .native(.base), owner: owner, amount: "1") }
        expectFailure { _ = try WalletRouteRequest(source: .native(.base), destination: .native(.ethereum), owner: owner, amount: "1", slippageBPS: 500) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let market = try WalletNetworkMarket.decode(Data("{\"ethereum\":{\"usd\":2000,\"last_updated_at\":1700000000},\"binancecoin\":{\"usd\":500,\"last_updated_at\":1699990000},\"polygon-ecosystem-token\":{\"usd\":-1,\"last_updated_at\":1700000000}}".utf8), now: now)
        check(market.count == 1)
        let v = WalletNetworkValuation.calculate([.ethereum: .init(network: .ethereum, raw: "1000000000000000000", fetchedAt: now), .base: .init(network: .base, raw: "2000000000000000000", fetchedAt: now), .bnb: .init(network: .bnb, raw: "0", fetchedAt: now), .polygon: .init(network: .polygon, raw: "1", fetchedAt: now)], prices: market, now: now)
        check(v.usd == 6000 && v.covered == 3 && v.partial)
        check(WalletNetworkValuation.calculate([:], prices: market, now: now).usd == nil)
        check(WalletNetworkValuation.calculate([.ethereum: .init(network: .ethereum, raw: "1", fetchedAt: now)], prices: market, now: now.addingTimeInterval(301)).usd == nil)
        check(WalletWeb3Policy.allows(chainID: "eip155:1", account: owner, requestedMethods: ["eth_accounts"], approvedNetworks: [.ethereum], approvedOwner: owner))
        for method in ["eth_sendTransaction", "personal_sign", "eth_signTypedData_v4", "wallet_switchEthereumChain"] { check(!WalletWeb3Policy.allows(chainID: "eip155:1", account: owner, requestedMethods: [method], approvedNetworks: [.ethereum], approvedOwner: owner)) }
        check(!WalletWeb3Policy.allows(chainID: "eip155:8453", account: owner, requestedMethods: ["eth_accounts"], approvedNetworks: [.ethereum], approvedOwner: owner))
        check(!WalletWeb3Policy.allows(chainID: "eip155:1", account: owner, requestedMethods: ["eth_accounts"], approvedNetworks: [.ethereum], approvedOwner: "0x2222222222222222222222222222222222222222"))
        print("PASS network expansion, portfolio, route preview, Web3 policy")
    }
}
