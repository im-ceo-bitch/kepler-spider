import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// All calls are read-only; allowlisted contracts, explicit network and account scope.
struct WalletNetworkRPCClient: Sendable {
    typealias RPC = @Sendable (String, String, Data) async throws -> String
    let rpc: RPC
    init(rpc: @escaping RPC = { endpoint, method, params in try await Self.live(endpoint, method, params) }) { self.rpc = rpc }
    static func live(_ endpoint: String, _ method: String, _ params: Data) async throws -> String {
        guard WalletEVMNetwork.allCases.flatMap(\.endpoints).contains(endpoint),
              ["eth_chainId", "eth_getBalance", "eth_call", "eth_getTransactionCount", "eth_estimateGas", "eth_gasPrice"].contains(method),
              let url = URL(string: endpoint), let array = try JSONSerialization.jsonObject(with: params) as? [Any] else { throw WalletExpansionError.invalid }
        let id = UUID().uuidString
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc":"2.0", "id":id, "method":method, "params":array])
        let data = try await WalletExpansionHTTP.load(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String:Any], json["jsonrpc"] as? String == "2.0", json["id"] as? String == id, json["error"] == nil || json["error"] is NSNull, let result = json["result"] as? String else { throw WalletExpansionError.mismatch }
        return result
    }
    func call(_ endpoint: String, _ method: String, _ params: [Any]) async throws -> String {
        try Task.checkCancellation()
        return try await rpc(endpoint, method, JSONSerialization.data(withJSONObject: params))
    }
    func verify(_ network: WalletEVMNetwork, _ endpoint: String) async throws {
        guard try WalletExactAmount.fromHex(await call(endpoint, "eth_chainId", [])) == String(network.id) else { throw WalletExpansionError.wrongNetwork }
    }
    func balance(_ asset: WalletNetworkAsset, owner: String, endpoint: String) async throws -> String {
        guard WalletNetworkAsset.quoteAssets.contains(asset), WalletNetworkReader.validAddress(owner), asset.network.endpoints.contains(endpoint) else { throw WalletExpansionError.invalid }
        if asset.isNative { return try WalletExactAmount.fromHex(await call(endpoint, "eth_getBalance", [owner,"latest"])) }
        let data = "0x70a08231" + String(repeating: "0", count: 24) + owner.dropFirst(2).lowercased()
        return try WalletExactAmount.abiWord(await call(endpoint, "eth_call", [["to":asset.contract,"data":data],"latest"]))
    }
    func snapshot(_ asset: WalletNetworkAsset, owner: String) async throws -> WalletTokenSnapshot {
        guard WalletNetworkAsset.quoteAssets.contains(asset), WalletNetworkReader.validAddress(owner) else { throw WalletExpansionError.invalid }
        var last: Error = WalletExpansionError.unavailable
        for endpoint in asset.network.endpoints {
            do {
                try await verify(asset.network, endpoint)
                let raw = try await balance(asset, owner: owner, endpoint: endpoint)
                try Task.checkCancellation()
                return .init(asset: asset, owner: owner.lowercased(), raw: raw, fetchedAt: Date())
            } catch { try Task.checkCancellation(); last = error }
        }
        throw last
    }
}

struct WalletTokenSnapshot: Sendable {
    let asset: WalletNetworkAsset
    let owner: String
    let raw: String
    let fetchedAt: Date
    var amount: String { WalletExactAmount.display(raw, decimals: asset.decimals) }
    func matches(asset: WalletNetworkAsset, owner: String, now: Date = Date(), maxAge: TimeInterval = 300) -> Bool {
        let age = now.timeIntervalSince(fetchedAt)
        return self.asset == asset && self.owner == owner.lowercased() && age >= 0 && age <= maxAge && WalletExactAmount.valid(raw)
    }
}

struct WalletAssetPortfolio {
    let usd: Decimal?
    let valued: Int
    let total: Int
    var partial: Bool { valued != total }
    static func calculate(owner: String, snapshots: [String: WalletTokenSnapshot], prices: [String: WalletNetworkPrice], assets: [WalletNetworkAsset] = WalletNetworkAsset.quoteAssets, now: Date = Date()) -> Self {
        let unique = Set(assets.filter { WalletNetworkAsset.quoteAssets.contains($0) })
        var sum = Decimal.zero, count = 0
        for asset in unique {
            guard let row = snapshots[asset.id], row.matches(asset: asset, owner: owner, now: now) else { continue }
            if row.raw == "0" { count += 1; continue }
            guard let price = prices[asset.marketID], price.fresh(at: now), price.usd > 0, !price.usd.isNaN,
                  let amount = Decimal(string: row.amount, locale: Locale(identifier: "en_US_POSIX")) else { continue }
            let value = amount * price.usd
            guard !value.isNaN, !(sum + value).isNaN else { continue }
            sum += value; count += 1
        }
        return .init(usd: count == 0 ? nil : sum, valued: count, total: unique.count)
    }
}

/// Read-only, immutable transfer simulation. A gas-price estimate is NOT a signing authorization.
/// Rollup L1-data fees and future fee changes are not included; the UI must label this limitation.
struct WalletNetworkTransferPreview: Sendable {
    let asset: WalletNetworkAsset
    let sender: String
    let recipient: String
    let rawAmount: String
    let gas: UInt64
    let gasPrice: UInt64
    let estimatedFee: String
    let nonce: UInt64
    let checkedAt: Date
    var feeDisplay: String { WalletExactAmount.display(estimatedFee, decimals: 18) + " " + asset.network.ticker }
    func isFresh(now: Date = Date()) -> Bool { let age = now.timeIntervalSince(checkedAt); return age >= 0 && age < 45 }
    static func fetch(asset: WalletNetworkAsset, sender: String, recipient: String, amount: String, client: WalletNetworkRPCClient = .init()) async throws -> Self {
        guard WalletNetworkAsset.quoteAssets.contains(asset), WalletNetworkReader.validAddress(sender), WalletNetworkReader.validAddress(recipient), sender.lowercased() != recipient.lowercased() else { throw WalletExpansionError.invalid }
        let units = try WalletExactAmount.parse(amount, decimals: asset.decimals)
        guard units != "0" else { throw WalletExpansionError.invalid }
        let amountHex = try WalletEVMUnits.hexFromDecimal(units)
        var last: Error = WalletExpansionError.unavailable
        for endpoint in asset.network.endpoints {
            do {
                let start = Date()
                try await client.verify(asset.network, endpoint)
                let native = try await client.balance(.native(asset.network), owner: sender, endpoint: endpoint)
                if !asset.isNative {
                    let tokens = try await client.balance(asset, owner: sender, endpoint: endpoint)
                    guard WalletExactAmount.compare(tokens, units) >= 0 else { throw WalletEVMPreflightError.insufficientTokens }
                }
                var tx = ["from": sender, "to": asset.isNative ? recipient : asset.contract, "value": asset.isNative ? amountHex : "0x0"]
                if !asset.isNative { tx["data"] = try WalletEVMUnits.transferData(to: recipient, baseUnits: units) }
                let estimate = try WalletEVMUnits.integer(await client.call(endpoint, "eth_estimateGas", [tx]), upperBound: 8_000_000)
                guard estimate >= 21_000 else { throw WalletExpansionError.invalid }
                let gas = estimate + estimate / 5
                let price = try WalletEVMUnits.integer(await client.call(endpoint, "eth_gasPrice", []), upperBound: 3_000_000_000_000)
                guard price > 0 else { throw WalletExpansionError.invalid }
                let fee = try WalletExactAmount.multiply(String(price), by: gas)
                let required = try WalletExactAmount.add(fee, asset.isNative ? units : "0")
                guard WalletExactAmount.compare(native, required) >= 0 else { throw WalletEVMPreflightError.insufficientETH }
                tx["gas"] = "0x" + String(gas, radix: 16)
                tx["gasPrice"] = "0x" + String(price, radix: 16)
                let simulation = try await client.call(endpoint, "eth_call", [tx, "pending"])
                if asset.isNative { try WalletEVMUnits.validateSimulation(simulation, asset: .eth) }
                else { try WalletEVMUnits.validateSimulation(simulation, asset: asset == .ethereumUSDT ? .usdt : .usdc) }
                let nonce = try WalletEVMUnits.integer(await client.call(endpoint, "eth_getTransactionCount", [sender,"pending"]), upperBound: 10_000_000_000)
                try await client.verify(asset.network, endpoint)
                try Task.checkCancellation()
                let result = Self(asset: asset, sender: sender, recipient: recipient, rawAmount: units, gas: gas, gasPrice: price, estimatedFee: fee, nonce: nonce, checkedAt: start)
                guard result.isFresh() else { throw WalletExpansionError.stale }; return result
            } catch { try Task.checkCancellation(); last = error }
        }
        throw last
    }
}
