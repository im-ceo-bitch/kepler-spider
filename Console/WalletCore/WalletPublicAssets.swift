import Foundation
import Combine

// Public read-only chain state. No seed phrase or private key is ever sent to an RPC provider.
// Public free endpoints may rate-limit; failures are displayed, never silently converted to zero.
enum WalletPublicRPCError: LocalizedError {
    case badHTTP(Int), badResponse, missingResult, invalidAmount

    var errorDescription: String? {
        switch self {
        case .badHTTP(let code): "Провайдер сети недоступен (HTTP \(code))."
        case .badResponse: "Некорректный ответ провайдера сети."
        case .missingResult: "Нет данных для этого адреса."
        case .invalidAmount: "Не удалось проверить баланс."
        }
    }
}

private struct RPCEnvelope: Decodable { let result: String?; let error: RPCFault? }
private struct RPCFault: Decodable { let code: Int; let message: String }
private struct SolanaResult: Decodable { let result: SolanaValue?; let error: RPCFault? }
private struct SolanaValue: Decodable { let value: UInt64 }
private struct BitcoinAddressResult: Decodable { let chain_stats: BitcoinStats; let mempool_stats: BitcoinStats }
private struct BitcoinStats: Decodable { let funded_txo_sum: Int64; let spent_txo_sum: Int64 }

private struct WalletBalanceSnapshot {
    let total: Decimal
    let confirmed: Decimal?
    let pendingDelta: Decimal?
    init(_ total: Decimal, confirmed: Decimal? = nil, pendingDelta: Decimal? = nil) {
        self.total = total; self.confirmed = confirmed; self.pendingDelta = pendingDelta
    }
}

private enum WalletPublicAssetClient {
    private static func fetch(_ url: URL, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 16
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WalletPublicRPCError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw WalletPublicRPCError.badHTTP(http.statusCode) }
        guard data.count < 300_000 else { throw WalletPublicRPCError.badResponse }
        return data
    }

    private static func get(_ endpoints: [String]) async throws -> Data {
        var last: Error = WalletPublicRPCError.badResponse
        for endpoint in endpoints {
            do {
                guard let url = URL(string: endpoint) else { continue }
                return try await fetch(url)
            } catch {
                if error is CancellationError { throw error }
                last = error
            }
        }
        throw last
    }

    private static func rpc(_ endpoints: [String], method: String, params: [Any]) async throws -> Data {
        let requestBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        var last: Error = WalletPublicRPCError.badResponse
        for endpoint in endpoints {
            do {
                guard let url = URL(string: endpoint) else { continue }
                let result = try await fetch(url, body: requestBody)
                // HTTP 200 can still contain a JSON-RPC error. Retry the secondary provider.
                guard let object = try JSONSerialization.jsonObject(with: result) as? [String: Any],
                      (object["error"] == nil || object["error"] is NSNull) else { throw WalletPublicRPCError.badResponse }
                return result
            } catch {
                if error is CancellationError { throw error }
                last = error
            }
        }
        throw last
    }

    private static let ethereumNodes = ["https://ethereum-rpc.publicnode.com", "https://cloudflare-eth.com"]
    private static let solanaNodes = ["https://api.mainnet-beta.solana.com", "https://solana-rpc.publicnode.com"]

    private static func decimalHex(_ input: String) throws -> Decimal {
        guard input.hasPrefix("0x"), input.count >= 3 else { throw WalletPublicRPCError.invalidAmount }
        var result = Decimal(0)
        for c in input.dropFirst(2) {
            guard let digit = c.hexDigitValue else { throw WalletPublicRPCError.invalidAmount }
            result = result * Decimal(16) + Decimal(digit)
        }
        return result
    }

    static func balance(chain: SpyderChain, address: String) async throws -> WalletBalanceSnapshot {
        switch chain {
        case .ethereum:
            let data = try await rpc(ethereumNodes, method: "eth_getBalance", params: [address, "latest"])
            let body = try JSONDecoder().decode(RPCEnvelope.self, from: data)
            guard body.error == nil, let hex = body.result else { throw WalletPublicRPCError.missingResult }
            return WalletBalanceSnapshot(try decimalHex(hex) / Decimal(string: "1000000000000000000")!)
        case .solana:
            let data = try await rpc(solanaNodes, method: "getBalance", params: [address, ["commitment": "confirmed"]])
            let body = try JSONDecoder().decode(SolanaResult.self, from: data)
            guard body.error == nil, let lamports = body.result?.value else { throw WalletPublicRPCError.missingResult }
            return WalletBalanceSnapshot(Decimal(string: String(lamports))! / Decimal(1_000_000_000))
        case .bitcoin:
            guard address.range(of: "^[a-zA-Z0-9]{26,90}$", options: .regularExpression) != nil else { throw WalletPublicRPCError.badResponse }
            let data = try await get(["https://blockstream.info/api/address/\(address)", "https://mempool.space/api/address/\(address)"])
            let body = try JSONDecoder().decode(BitcoinAddressResult.self, from: data)
            let confirmed = body.chain_stats.funded_txo_sum - body.chain_stats.spent_txo_sum
            let pending = body.mempool_stats.funded_txo_sum - body.mempool_stats.spent_txo_sum
            guard confirmed >= 0, confirmed + pending >= 0 else { throw WalletPublicRPCError.invalidAmount }
            return WalletBalanceSnapshot(Decimal(confirmed + pending) / Decimal(100_000_000),
                confirmed: Decimal(confirmed) / Decimal(100_000_000),
                pendingDelta: Decimal(pending) / Decimal(100_000_000))
        }
    }

    // Only issuer-verified Ethereum ERC-20 contracts. Each token has 6 decimals.
    static func erc20Balance(contract: String, holder: String) async throws -> Decimal {
        guard holder.hasPrefix("0x"), holder.count == 42, contract.hasPrefix("0x"), contract.count == 42 else {
            throw WalletPublicRPCError.badResponse
        }
        let callData = "0x70a08231" + String(repeating: "0", count: 24) + String(holder.dropFirst(2)).lowercased()
        let args: [Any] = [["to": contract, "data": callData], "latest"]
        let data = try await rpc(ethereumNodes, method: "eth_call", params: args)
        let body = try JSONDecoder().decode(RPCEnvelope.self, from: data)
        guard body.error == nil, let hex = body.result else { throw WalletPublicRPCError.missingResult }
        return try decimalHex(hex) / Decimal(1_000_000)
    }

    static func prices() async throws -> (native: [SpyderChain: Decimal], stable: [String: Decimal]) {
        let endpoint = "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana,tether,usd-coin&vs_currencies=usd"
        let data = try await get([endpoint])
        let object = try JSONSerialization.jsonObject(with: data) as? [String: [String: NSNumber]]
        guard let object else { throw WalletPublicRPCError.badResponse }
        var result: [SpyderChain: Decimal] = [:]
        for chain in SpyderChain.allCases {
            let price = object[chain.rawValue]?["usd"]?.doubleValue ?? 0
            if price > 0 && price.isFinite { result[chain] = Decimal(price) }
        }
        let stable = ["USDT": "tether", "USDC": "usd-coin"]
        var stablePrices: [String: Decimal] = [:]
        for (ticker, id) in stable {
            let value = object[id]?["usd"]?.doubleValue ?? 0
            if value > 0 && value.isFinite { stablePrices[ticker] = Decimal(value) }
        }
        guard !result.isEmpty || !stablePrices.isEmpty else { throw WalletPublicRPCError.missingResult }
        return (result, stablePrices)
    }
}

@MainActor
final class WalletPublicAssetsStore: ObservableObject {
    @Published private(set) var balances: [SpyderChain: Decimal] = [:]
    @Published private(set) var prices: [SpyderChain: Decimal] = [:]
    @Published private(set) var failures: [SpyderChain: String] = [:]
    @Published private(set) var stablecoins: [String: Decimal] = [:]
    @Published private(set) var stablecoinPrices: [String: Decimal] = [:]
    @Published private(set) var stablecoinFailures: [String: String] = [:]
    @Published private(set) var updatedAt: Date?
    @Published private(set) var loading = false
    @Published private(set) var priceError: String?
    @Published private(set) var bitcoinConfirmed: Decimal?
    @Published private(set) var bitcoinPendingDelta: Decimal?
    private var refreshGeneration = UUID()

    func resetForAccountChange() {
        refreshGeneration = UUID()
        balances = [:]
        prices = [:]
        failures = [:]
        stablecoins = [:]
        stablecoinPrices = [:]
        stablecoinFailures = [:]
        updatedAt = nil
        priceError = nil
        bitcoinConfirmed = nil
        bitcoinPendingDelta = nil
        loading = false
    }

    // Apply a verified, time-stamped public market snapshot; wallet addresses are not involved.
    // CoinGecko is also queried by the legacy balance screen as a fallback until migration.
    func applyMarketQuotes(_ quotes: [String: WalletMarketQuote]) {
        for chain in SpyderChain.allCases {
            if let quote = quotes[chain.ticker], !quote.isStale(), let usd = quote.decimalUSD {
                prices[chain] = usd
            }
        }
        for ticker in ["USDT", "USDC"] {
            if let quote = quotes[ticker], !quote.isStale(), let usd = quote.decimalUSD {
                stablecoinPrices[ticker] = usd
            }
        }
    }

    // Use only the amounts actually retrieved. Failures never become fake zeroes.
    // Label the displayed estimate as partial when any network or price is missing.
    var totalUSD: Decimal? {
        var result = Decimal.zero
        var found = false
        for (chain, amount) in balances {
            if let price = prices[chain] { result += amount * price; found = true }
        }
        for (ticker, amount) in stablecoins {
            if let price = stablecoinPrices[ticker] { result += amount * price; found = true }
        }
        return found ? result : nil
    }

    var isPartialEstimate: Bool {
        balances.count != SpyderChain.allCases.count ||
        prices.count != SpyderChain.allCases.count ||
        stablecoins.count != 2 || stablecoinPrices.count != 2
    }

    static func formatted(_ value: Decimal, fractionDigits: Int = 8) -> String {
        let format = NumberFormatter()
        format.numberStyle = .decimal
        format.minimumFractionDigits = 0
        format.maximumFractionDigits = fractionDigits
        return format.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }

    func refresh(addresses: [SpyderAddress]) async {
        guard !loading, !addresses.isEmpty else { return }
        let generation = refreshGeneration
        loading = true
        defer { if generation == refreshGeneration { loading = false } }
        var read: [SpyderChain: Decimal] = [:]
        var errors: [SpyderChain: String] = [:]
        var bitcoin: WalletBalanceSnapshot?
        await withTaskGroup(of: (SpyderChain, Result<WalletBalanceSnapshot, Error>).self) { group in
            for address in addresses {
                group.addTask {
                    do { return (address.chain, .success(try await WalletPublicAssetClient.balance(chain: address.chain, address: address.value))) }
                    catch { return (address.chain, .failure(error)) }
                }
            }
            for await (chain, result) in group {
                switch result {
                case .success(let amount):
                    read[chain] = amount.total
                    if chain == .bitcoin { bitcoin = amount }
                case .failure(let error): errors[chain] = error.localizedDescription
                }
            }
        }
        guard generation == refreshGeneration else { return }
        // An API error must not leave a stale displayed amount from an earlier refresh.
        balances = read
        failures = errors
        bitcoinConfirmed = bitcoin?.confirmed
        bitcoinPendingDelta = bitcoin?.pendingDelta
        if let ethereumAddress = addresses.first(where: { $0.chain == .ethereum })?.value {
            let contracts = WalletTokenCatalog.ethereumERC20
            var amounts: [String: Decimal] = [:]
            var problems: [String: String] = [:]
            await withTaskGroup(of: (String, Result<Decimal, Error>).self) { group in
                for token in contracts {
                    group.addTask {
                        do { return (token.ticker, .success(try await WalletPublicAssetClient.erc20Balance(contract: token.contract, holder: ethereumAddress))) }
                        catch { return (token.ticker, .failure(error)) }
                    }
                }
                for await (name, value) in group {
                    switch value {
                    case .success(let amount): amounts[name] = amount
                    case .failure(let error): problems[name] = error.localizedDescription
                    }
                }
            }
            guard generation == refreshGeneration else { return }
            stablecoins = amounts
            stablecoinFailures = problems
        } else {
            stablecoins = [:]
            stablecoinFailures = [:]
        }
        do {
            let market = try await WalletPublicAssetClient.prices()
            guard generation == refreshGeneration else { return }
            prices = market.native
            stablecoinPrices = market.stable
            priceError = nil
        } catch {
            guard generation == refreshGeneration else { return }
            prices = [:]
            stablecoinPrices = [:]
            priceError = "USD-курсы недоступны: " + error.localizedDescription
        }
        if generation == refreshGeneration { updatedAt = Date() }
    }
}
