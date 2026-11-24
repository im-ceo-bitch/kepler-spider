import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// This service deliberately discards calldata and approval addresses. A quote is not an authorization.
struct WalletRouteRequest: Equatable, Sendable {
    let source: WalletNetworkAsset
    let destination: WalletNetworkAsset
    let owner: String
    let rawAmount: String
    let slippageBPS: Int
    init(source: WalletNetworkAsset, destination: WalletNetworkAsset, owner: String, amount: String, slippageBPS: Int = 50) throws {
        guard WalletNetworkAsset.quoteAssets.contains(source), WalletNetworkAsset.quoteAssets.contains(destination), source != destination,
              WalletNetworkReader.validAddress(owner), (1...100).contains(slippageBPS) else { throw WalletExpansionError.invalid }
        let raw = try WalletExactAmount.parse(amount, decimals: source.decimals)
        guard raw != "0" else { throw WalletExpansionError.invalid }
        self.source = source; self.destination = destination; self.owner = owner; self.rawAmount = raw; self.slippageBPS = slippageBPS
    }
    func url() throws -> URL {
        var parts = URLComponents(string: "https://li.quest/v1/quote")!
        let slip = "0." + String(repeating: "0", count: 4 - String(slippageBPS).count) + String(slippageBPS)
        parts.queryItems = ["fromChain": String(source.network.id), "toChain": String(destination.network.id), "fromToken": source.contract, "toToken": destination.contract, "fromAddress": owner, "toAddress": owner, "fromAmount": rawAmount, "slippage": slip].sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = parts.url else { throw WalletExpansionError.invalid }; return url
    }
}

struct WalletRoutePreview: Sendable {
    let request: WalletRouteRequest
    let expected: String
    let minimum: String
    let tool: String
    let duration: Int
    let receivedAt: Date
    func isFresh(now: Date = Date()) -> Bool { let age = now.timeIntervalSince(receivedAt); return age >= 0 && age < 45 }

    private struct Reply: Decodable {
        struct Token: Decodable { let address: String; let chainId: Int; let decimals: Int }
        struct Action: Decodable { let fromChainId: Int; let toChainId: Int; let fromToken: Token; let toToken: Token; let fromAddress: String; let toAddress: String; let fromAmount: String; let slippage: Double }
        struct Estimate: Decodable { let fromAmount: String; let toAmount: String; let toAmountMin: String; let executionDuration: Int }
        let tool: String; let action: Action; let estimate: Estimate
    }
    static func decode(_ data: Data, request: WalletRouteRequest, now: Date = Date()) throws -> Self {
        guard (1...512_000).contains(data.count) else { throw WalletExpansionError.invalid }
        let reply = try JSONDecoder().decode(Reply.self, from: data), a = reply.action, e = reply.estimate
        func match(_ token: Reply.Token, _ asset: WalletNetworkAsset) -> Bool { token.address.lowercased() == asset.contract && token.chainId == asset.network.id && token.decimals == asset.decimals }
        guard a.fromChainId == request.source.network.id, a.toChainId == request.destination.network.id,
              match(a.fromToken, request.source), match(a.toToken, request.destination),
              a.fromAddress.lowercased() == request.owner.lowercased(), a.toAddress.lowercased() == request.owner.lowercased(),
              a.fromAmount == request.rawAmount, e.fromAmount == request.rawAmount,
              a.slippage.isFinite, abs(a.slippage - Double(request.slippageBPS)/10_000) < 0.000000001,
              WalletExactAmount.valid(e.toAmount), WalletExactAmount.valid(e.toAmountMin), e.toAmountMin != "0",
              WalletExactAmount.compare(e.toAmountMin, e.toAmount) <= 0,
              (0...604800).contains(e.executionDuration), reply.tool.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else { throw WalletExpansionError.mismatch }
        return .init(request: request, expected: e.toAmount, minimum: e.toAmountMin, tool: reply.tool, duration: e.executionDuration, receivedAt: now)
    }
    static func fetch(_ request: WalletRouteRequest) async throws -> Self {
        let start = Date()
        let data = try await WalletExpansionHTTP.load(URLRequest(url: request.url(), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 18))
        let result = try decode(data, request: request, now: start)
        guard result.isFresh() else { throw WalletExpansionError.stale }; return result
    }
}

/// WalletConnect integration boundary: approve only explicitly scoped read-only EVM methods.
/// No transport or signing is wired to this policy until WalletKit is configured.
enum WalletWeb3Policy {
    static let methods: Set<String> = ["eth_accounts", "eth_chainId"]
    static func allows(chainID: String, account: String, requestedMethods: Set<String>, approvedNetworks: Set<WalletEVMNetwork>, approvedOwner: String) -> Bool {
        guard let network = WalletEVMNetwork.allCases.first(where: { "eip155:\($0.id)" == chainID }), approvedNetworks.contains(network),
              WalletNetworkReader.validAddress(account), WalletNetworkReader.validAddress(approvedOwner), account.lowercased() == approvedOwner.lowercased(),
              !requestedMethods.isEmpty, requestedMethods.isSubset(of: methods) else { return false }
        return true
    }
}
