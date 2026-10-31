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

private enum WalletPublicAssetClient {
    private static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 16
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WalletPublicRPCError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw WalletPublicRPCError.badHTTP(http.statusCode) }
        guard data.count < 300_000 else { throw WalletPublicRPCError.badResponse }
        return data
    }

    private static func rpc(_ endpoint: String, method: String, params: [Any]) async throws -> Data {
        guard let url = URL(string: endpoint) else { throw WalletPublicRPCError.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 16
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WalletPublicRPCError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw WalletPublicRPCError.badHTTP(http.statusCode) }
        guard data.count < 300_000 else { throw WalletPublicRPCError.badResponse }
        return data
    }

    private static func decimalHex(_ input: String) throws -> Decimal {
        guard input.hasPrefix("0x"), input.count >= 3 else { throw WalletPublicRPCError.invalidAmount }
        var result = Decimal(0)
        for c in input.dropFirst(2) {
            guard let digit = c.hexDigitValue else { throw WalletPublicRPCError.invalidAmount }
            result = result * Decimal(16) + Decimal(digit)
        }
        return result
    }

    static func balance(chain: SpyderChain, address: String) async throws -> Decimal {
        switch chain {
        case .ethereum:
            let data = try await rpc("https://ethereum-rpc.publicnode.com", method: "eth_getBalance", params: [address, "latest"])
            let body = try JSONDecoder().decode(RPCEnvelope.self, from: data)
            guard body.error == nil, let hex = body.result else { throw WalletPublicRPCError.missingResult }
            return try decimalHex(hex) / Decimal(string: "1000000000000000000")!
        case .solana:
            let data = try await rpc("https://api.mainnet.solana.com", method: "getBalance", params: [address, ["commitment": "confirmed"]])
            let body = try JSONDecoder().decode(SolanaResult.self, from: data)
            guard body.error == nil, let lamports = body.result?.value else { throw WalletPublicRPCError.missingResult }
            return Decimal(string: String(lamports))! / Decimal(1_000_000_000)
        case .bitcoin:
            guard let url = URL(string: "https://blockstream.info/api/address/\(address)") else { throw WalletPublicRPCError.badResponse }
            let data = try await get(url)
            let body = try JSONDecoder().decode(BitcoinAddressResult.self, from: data)
            let confirmed = body.chain_stats.funded_txo_sum - body.chain_stats.spent_txo_sum
            let pending = body.mempool_stats.funded_txo_sum - body.mempool_stats.spent_txo_sum
            guard confirmed >= 0, confirmed + pending >= 0 else { throw WalletPublicRPCError.invalidAmount }
            return Decimal(confirmed + pending) / Decimal(100_000_000)
        }
    }

    // Only issuer-verified Ethereum ERC-20 contracts. Each token has 6 decimals.
    static func erc20Balance(contract: String, holder: String) async throws -> Decimal {
        guard holder.hasPrefix("0x"), holder.count == 42, contract.hasPrefix("0x"), contract.count == 42 else {
            throw WalletPublicRPCError.badResponse
        }
        let callData = "0x70a08231" + String(repeating: "0", count: 24) + String(holder.dropFirst(2)).lowercased()
        let args: [Any] = [["to": contract, "data": callData], "latest"]
        let data = try await rpc("https://ethereum-rpc.publicnode.com", method: "eth_call", params: args)
        let body = try JSONDecoder().decode(RPCEnvelope.self, from: data)
        guard body.error == nil, let hex = body.result else { throw WalletPublicRPCError.missingResult }
        return try decimalHex(hex) / Decimal(1_000_000)
    }

    static func prices() async throws -> [SpyderChain: Decimal] {
        let endpoint = "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana&vs_currencies=usd"
        guard let url = URL(string: endpoint) else { throw WalletPublicRPCError.badResponse }
        let data = try await get(url)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: [String: NSNumber]]
        guard let object else { throw WalletPublicRPCError.badResponse }
        var result: [SpyderChain: Decimal] = [:]
        for chain in SpyderChain.allCases {
            let price = object[chain.rawValue]?["usd"]?.doubleValue ?? 0
            if price > 0 && price.isFinite { result[chain] = Decimal(price) }
        }
        guard result.count == SpyderChain.allCases.count else { throw WalletPublicRPCError.missingResult }
        return result
    }
}

@MainActor
final class WalletPublicAssetsStore: ObservableObject {
    @Published private(set) var balances: [SpyderChain: Decimal] = [:]
    @Published private(set) var prices: [SpyderChain: Decimal] = [:]
    @Published private(set) var failures: [SpyderChain: String] = [:]
    @Published private(set) var stablecoins: [String: Decimal] = [:]
    @Published private(set) var stablecoinFailures: [String: String] = [:]
    @Published private(set) var updatedAt: Date?
    @Published private(set) var loading = false
    @Published private(set) var priceError: String?

    var totalUSD: Decimal? {
        guard balances.count == SpyderChain.allCases.count, prices.count == SpyderChain.allCases.count else { return nil }
        var value = Decimal.zero
        for (chain, amount) in balances {
            guard let price = prices[chain] else { return nil }
            value += amount * price
        }
        // Portfolio estimate covers only the three native coins; stablecoins shown separately.
        return value
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
        loading = true
        defer { loading = false }
        var read: [SpyderChain: Decimal] = [:]
        var errors: [SpyderChain: String] = [:]
        await withTaskGroup(of: (SpyderChain, Result<Decimal, Error>).self) { group in
            for address in addresses {
                group.addTask {
                    do { return (address.chain, .success(try await WalletPublicAssetClient.balance(chain: address.chain, address: address.value))) }
                    catch { return (address.chain, .failure(error)) }
                }
            }
            for await (chain, result) in group {
                switch result {
                case .success(let amount): read[chain] = amount
                case .failure(let error): errors[chain] = error.localizedDescription
                }
            }
        }
        // An API error must not leave a stale displayed amount from an earlier refresh.
        balances = read
        failures = errors
        if let ethereumAddress = addresses.first(where: { $0.chain == .ethereum })?.value {
            let contracts = [
                "USDT": "0xdac17f958d2ee523a2206206994597c13d831ec7",
                "USDC": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
            ]
            var amounts: [String: Decimal] = [:]
            var problems: [String: String] = [:]
            await withTaskGroup(of: (String, Result<Decimal, Error>).self) { group in
                for (name, contract) in contracts {
                    group.addTask {
                        do { return (name, .success(try await WalletPublicAssetClient.erc20Balance(contract: contract, holder: ethereumAddress))) }
                        catch { return (name, .failure(error)) }
                    }
                }
                for await (name, value) in group {
                    switch value {
                    case .success(let amount): amounts[name] = amount
                    case .failure(let error): problems[name] = error.localizedDescription
                    }
                }
            }
            stablecoins = amounts
            stablecoinFailures = problems
        } else {
            stablecoins = [:]
            stablecoinFailures = [:]
        }
        do {
            prices = try await WalletPublicAssetClient.prices()
            priceError = nil
        } catch {
            prices = [:]
            priceError = "USD-курсы недоступны: " + error.localizedDescription
        }
        updatedAt = Date()
    }
}
