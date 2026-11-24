import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Separate from SpyderChain: EVM networks share a derived address, not a balance or transaction namespace.
enum WalletEVMNetwork: Int, CaseIterable, Identifiable, Codable, Sendable {
    case ethereum = 1, arbitrum = 42161, optimism = 10, base = 8453, bnb = 56, polygon = 137
    var id: Int { rawValue }
    var name: String {
        switch self { case .ethereum: "Ethereum"; case .arbitrum: "Arbitrum One"; case .optimism: "OP Mainnet"; case .base: "Base"; case .bnb: "BNB Smart Chain"; case .polygon: "Polygon PoS" }
    }
    var ticker: String { switch self { case .bnb: "BNB"; case .polygon: "POL"; default: "ETH" } }
    var marketID: String { switch self { case .bnb: "binancecoin"; case .polygon: "polygon-ecosystem-token"; default: "ethereum" } }
    var endpoints: [String] {
        switch self {
        case .ethereum: ["https://ethereum-rpc.publicnode.com", "https://eth.llamarpc.com"]
        case .arbitrum: ["https://arb1.arbitrum.io/rpc", "https://arbitrum-one-rpc.publicnode.com"]
        case .optimism: ["https://mainnet.optimism.io", "https://optimism-rpc.publicnode.com"]
        case .base: ["https://mainnet.base.org", "https://base-rpc.publicnode.com"]
        case .bnb: ["https://bsc-dataseed.bnbchain.org", "https://bsc-rpc.publicnode.com"]
        case .polygon: ["https://polygon-rpc.com", "https://polygon-bor-rpc.publicnode.com"]
        }
    }
}

enum WalletExpansionError: Error, LocalizedError {
    case invalid, unavailable, wrongNetwork, stale, mismatch
    var errorDescription: String? {
        switch self {
        case .invalid: "Invalid amount or address."
        case .unavailable: "Provider unavailable. Try again later."
        case .wrongNetwork: "RPC returned a different chain."
        case .stale: "Quote expired. Request a new quote."
        case .mismatch: "Provider response does not match the request."
        }
    }
}

/// Canonical base-unit strings; no floating point or Decimal conversion before display.
enum WalletExactAmount {
    static let max = "115792089237316195423570985008687907853269984665640564039457584007913129639935"
    static func valid(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 78 && s.utf8.allSatisfy { (48...57).contains($0) } && (s == "0" || s.first != "0") && (s.count < max.count || (s.count == max.count && s <= max))
    }
    static func compare(_ a: String, _ b: String) -> Int { a.count == b.count ? (a == b ? 0 : (a < b ? -1 : 1)) : (a.count < b.count ? -1 : 1) }
    static func fromHex(_ s: String) throws -> String {
        guard s.hasPrefix("0x"), (3...66).contains(s.count), s == "0x0" || s.dropFirst(2).first != "0" else { throw WalletExpansionError.invalid }
        var digits = [0]
        for byte in s.utf8.dropFirst(2) {
            let n: Int
            switch byte { case 48...57: n = Int(byte-48); case 65...70: n = Int(byte-55); case 97...102: n = Int(byte-87); default: throw WalletExpansionError.invalid }
            var carry = n
            for i in digits.indices { let x = digits[i]*16+carry; digits[i] = x % 10; carry = x / 10 }
            while carry > 0 { digits.append(carry % 10); carry /= 10 }
        }
        return digits.reversed().map(String.init).joined()
    }
    static func parse(_ input: String, decimals: Int) throws -> String {
        guard (0...36).contains(decimals), input.utf8.count <= 115 else { throw WalletExpansionError.invalid }
        let p = input.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(p.count), !p[0].isEmpty, p.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { throw WalletExpansionError.invalid }
        let fraction = p.count == 2 ? String(p[1]) : ""
        guard fraction.count <= decimals else { throw WalletExpansionError.invalid }
        let combined = String(p[0]) + fraction + String(repeating: "0", count: decimals-fraction.count)
        let stripped = String(combined.drop(while: { $0 == "0" }))
        let raw = stripped.isEmpty ? "0" : stripped
        guard valid(raw) else { throw WalletExpansionError.invalid }; return raw
    }
    static func display(_ raw: String, decimals: Int) -> String {
        guard valid(raw), (0...36).contains(decimals) else { return "—" }
        guard decimals > 0 else { return raw }
        let padded = String(repeating: "0", count: Swift.max(0, decimals+1-raw.count)) + raw
        let whole = padded.dropLast(decimals), tail = String(padded.suffix(decimals).reversed().drop(while: { $0 == "0" }).reversed())
        return String(whole) + (tail.isEmpty ? "" : "." + tail)
    }
}

struct WalletNetworkAsset: Hashable, Identifiable, Sendable {
    let network: WalletEVMNetwork
    let contract: String
    let ticker: String
    let decimals: Int
    static let nativeContract = "0x0000000000000000000000000000000000000000"
    var id: String { "eip155:\(network.rawValue)/\(contract.lowercased())" }
    static func native(_ network: WalletEVMNetwork) -> Self { .init(network: network, contract: nativeContract, ticker: network.ticker, decimals: 18) }
    static let ethereumUSDC = Self(network: .ethereum, contract: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", ticker: "USDC", decimals: 6)
    static var quoteAssets: [Self] { WalletEVMNetwork.allCases.map(native) + [ethereumUSDC] }
}

struct WalletNetworkBalance: Identifiable, Sendable {
    let network: WalletEVMNetwork
    let raw: String
    let fetchedAt: Date
    var id: Int { network.id }
    var amount: String { WalletExactAmount.display(raw, decimals: 18) }
}

/// Injectable, read-only transport, strict response IDs and chain validation. No signing interface.
struct WalletNetworkReader {
    typealias RPC = @Sendable (String, String, [String]) async throws -> String
    let rpc: RPC
    init(rpc: @escaping RPC = { endpoint, method, params in try await WalletNetworkReader.liveRPC(endpoint: endpoint, method: method, params: params) }) { self.rpc = rpc }
    static func validAddress(_ s: String) -> Bool { s.range(of: "^0x[0-9a-fA-F]{40}$", options: .regularExpression) != nil && s.lowercased() != WalletNetworkAsset.nativeContract }
    func balance(network: WalletEVMNetwork, address: String) async throws -> WalletNetworkBalance {
        guard Self.validAddress(address) else { throw WalletExpansionError.invalid }
        var last: Error = WalletExpansionError.unavailable
        for endpoint in network.endpoints {
            do {
                try Task.checkCancellation()
                let chain = try await rpc(endpoint, "eth_chainId", [])
                guard try WalletExactAmount.fromHex(chain) == String(network.id) else { throw WalletExpansionError.wrongNetwork }
                let raw = try WalletExactAmount.fromHex(await rpc(endpoint, "eth_getBalance", [address, "latest"]))
                try Task.checkCancellation()
                return .init(network: network, raw: raw, fetchedAt: Date())
            } catch { try Task.checkCancellation(); last = error }
        }
        throw last
    }
    static func liveRPC(endpoint: String, method: String, params: [String]) async throws -> String {
        guard ["eth_chainId", "eth_getBalance"].contains(method), let url = URL(string: endpoint) else { throw WalletExpansionError.invalid }
        let id = UUID().uuidString
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        let bytes = try await WalletExpansionHTTP.load(request)
        guard let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], json["jsonrpc"] as? String == "2.0", json["id"] as? String == id, json["error"] == nil || json["error"] is NSNull, let result = json["result"] as? String else { throw WalletExpansionError.mismatch }
        return result
    }
}

enum WalletExpansionHTTP {
    static func load(_ request: URLRequest) async throws -> Data {
        guard let url = request.url, url.scheme == "https", url.user == nil, url.password == nil else { throw WalletExpansionError.invalid }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 20
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: WalletEVMNoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), WalletEVMNoRedirect.matches(http.url, url), (1...512_000).contains(data.count) else { throw WalletExpansionError.unavailable }
        return data
    }
}

struct WalletNetworkPrice: Sendable {
    let usd: Decimal
    let updatedAt: Date
    func fresh(at now: Date) -> Bool { let age = now.timeIntervalSince(updatedAt); return age >= -60 && age <= 900 }
}

struct WalletNetworkValuation {
    let usd: Decimal?
    let covered: Int
    let expected: Int
    var partial: Bool { covered != expected }
    static func calculate(_ balances: [WalletEVMNetwork: WalletNetworkBalance], prices: [String: WalletNetworkPrice], now: Date) -> Self {
        var sum = Decimal.zero, covered = 0
        for network in WalletEVMNetwork.allCases {
            guard let balance = balances[network], balance.network == network,
                  WalletExactAmount.valid(balance.raw), now.timeIntervalSince(balance.fetchedAt) >= -1,
                  now.timeIntervalSince(balance.fetchedAt) <= 300 else { continue }
            if balance.raw == "0" { covered += 1; continue }
            guard let price = prices[network.marketID], price.fresh(at: now), price.usd > 0,
                  let amount = Decimal(string: balance.amount, locale: Locale(identifier: "en_US_POSIX")) else { continue }
            let value = amount * price.usd
            guard !value.isNaN, !(sum + value).isNaN else { continue }
            sum += value; covered += 1
        }
        return .init(usd: covered == 0 ? nil : sum, covered: covered, expected: WalletEVMNetwork.allCases.count)
    }
}

enum WalletNetworkMarket {
    private struct Row: Decodable { let usd: Decimal; let last_updated_at: Int64 }
    static func decode(_ data: Data, now: Date = Date()) throws -> [String: WalletNetworkPrice] {
        let rows = try JSONDecoder().decode([String: Row].self, from: data)
        let ids = Set(WalletEVMNetwork.allCases.map(\.marketID))
        var result: [String: WalletNetworkPrice] = [:]
        for (id, row) in rows where ids.contains(id) && row.usd > 0 && row.usd <= 1_000_000_000 && !row.usd.isNaN {
            let price = WalletNetworkPrice(usd: row.usd, updatedAt: Date(timeIntervalSince1970: TimeInterval(row.last_updated_at)))
            if price.fresh(at: now) { result[id] = price }
        }
        return result
    }
    static func fetch() async throws -> [String: WalletNetworkPrice] {
        var parts = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price")!
        parts.queryItems = [.init(name: "ids", value: Set(WalletEVMNetwork.allCases.map(\.marketID)).sorted().joined(separator: ",")), .init(name: "vs_currencies", value: "usd"), .init(name: "include_last_updated_at", value: "true")]
        guard let url = parts.url else { throw WalletExpansionError.invalid }
        return try decode(await WalletExpansionHTTP.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)))
    }
}
