import Foundation
import Combine

// Read-only chain activity. Never infer amounts for transactions whose balance delta is unknown.
// Public endpoints are optional data sources, NOT a consensus or signing authority.
struct WalletChainActivity: Identifiable, Hashable {
    enum State: String { case pending, confirmed, failed }
    let id: String
    let chain: SpyderChain
    let hash: String
    let timestamp: Date?
    let state: State
    let direction: String
    let amount: Decimal?
    let symbol: String
    let explorerURL: URL
}

private enum WalletActivityClient {
    static func fetch(_ address: SpyderAddress) async throws -> [WalletChainActivity] {
        switch address.chain {
        case .bitcoin: return try await bitcoin(address.value)
        case .ethereum: return try await ethereum(address.value)
        case .solana: return try await solana(address.value)
        }
    }

    private static func http(_ endpoints: [URL]) async throws -> Data {
        var lastError: Error = URLError(.cannotConnectToHost)
        for url in endpoints {
            do {
                var request = URLRequest(url: url)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 14
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode), data.count <= 2_000_000 else {
                    throw WalletPublicRPCError.badResponse
                }
                return data
            } catch {
                if error is CancellationError { throw error }
                lastError = error
            }
        }
        throw lastError
    }

    private struct BTCIO: Decodable { let scriptpubkey_address: String?; let value: Int64 }
    private struct BTCVin: Decodable { let prevout: BTCIO? }
    private struct BTCStatus: Decodable { let confirmed: Bool; let block_time: TimeInterval? }
    private struct BTCTx: Decodable { let txid: String; let vin: [BTCVin]; let vout: [BTCIO]; let status: BTCStatus }

    private static func bitcoin(_ address: String) async throws -> [WalletChainActivity] {
        guard !address.isEmpty, address.range(of: "^[a-zA-Z0-9]{26,90}$", options: .regularExpression) != nil else { throw WalletPublicRPCError.badResponse }
        let data = try await http(["https://blockstream.info/api/address/\(address)/txs", "https://mempool.space/api/address/\(address)/txs"].compactMap(URL.init(string:)))
        let rows = try JSONDecoder().decode([BTCTx].self, from: data)
        return rows.prefix(35).compactMap { item in
            guard item.txid.count == 64, item.txid.allSatisfy(\.isHexDigit),
                  let url = URL(string: "https://mempool.space/tx/\(item.txid)") else { return nil }
            let incoming = item.vout.filter { $0.scriptpubkey_address == address }.reduce(Int64(0)) { $0 + $1.value }
            let outgoing = item.vin.compactMap(\.prevout).filter { $0.scriptpubkey_address == address }.reduce(Int64(0)) { $0 + $1.value }
            let delta = incoming - outgoing
            return WalletChainActivity(id: "btc:\(item.txid)", chain: .bitcoin, hash: item.txid,
                                       timestamp: item.status.block_time.map(Date.init(timeIntervalSince1970:)),
                                       state: item.status.confirmed ? .confirmed : .pending,
                                       direction: delta < 0 ? "Отправлено" : "Получено",
                                       amount: Decimal(abs(delta)) / Decimal(100_000_000), symbol: "BTC", explorerURL: url)
        }
    }

    private struct ETHAddress: Decodable { let hash: String? }
    private struct ETHTx: Decodable {
        let hash: String
        let from: ETHAddress?
        let to: ETHAddress?
        let value: String?
        let timestamp: String?
        let status: String?
    }
    private struct ETHResult: Decodable { let items: [ETHTx] }

    private static func ethereum(_ address: String) async throws -> [WalletChainActivity] {
        guard address.range(of: "^0x[a-fA-F0-9]{40}$", options: .regularExpression) != nil else { throw WalletPublicRPCError.badResponse }
        let data = try await http(["https://eth.blockscout.com/api/v2/addresses/\(address)/transactions", "https://eth.blockscout.com/api/v2/addresses/\(address)/transactions?filter=to"].compactMap(URL.init(string:)))
        let result = try JSONDecoder().decode(ETHResult.self, from: data)
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let alternate = ISO8601DateFormatter()
        let native = result.items.prefix(35).compactMap { item -> WalletChainActivity? in
            guard item.hash.range(of: "^0x[a-fA-F0-9]{64}$", options: .regularExpression) != nil,
                  let url = URL(string: "https://etherscan.io/tx/\(item.hash)") else { return nil }
            let outgoing = item.from?.hash?.lowercased() == address.lowercased()
            let amount = item.value.flatMap(Decimal.init(string:)).map { $0 / Decimal(string: "1000000000000000000")! }
            let status = (item.status ?? "").lowercased()
            let state: WalletChainActivity.State = status == "error" ? .failed :
                (status == "ok" || status == "success" ? .confirmed : .pending)
            return WalletChainActivity(id: "eth:\(item.hash)", chain: .ethereum, hash: item.hash,
                                       timestamp: item.timestamp.flatMap { parser.date(from: $0) ?? alternate.date(from: $0) },
                                       state: state, direction: outgoing ? "Отправлено" : "Получено",
                                       amount: amount, symbol: "ETH", explorerURL: url)
        }
        // ERC-20 transfers are separate from native ETH operations in Blockscout.
        // Only allowlisted Ethereum contracts are identified as USDT / USDC.
        let tokenURL = "https://eth.blockscout.com/api/v2/addresses/\(address)/token-transfers?type=ERC-20"
        guard let data = try? await http([URL(string: tokenURL)].compactMap { $0 }),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["items"] as? [[String: Any]] else { return native }
        let transfers: [WalletChainActivity] = rows.prefix(35).enumerated().compactMap { index, item in
            guard let token = item["token"] as? [String: Any],
                  let contract = token["address_hash"] as? String,
                  let token = WalletTokenCatalog.verifiedEthereumToken(contract: contract),
                  let hash = item["tx_hash"] as? String,
                  hash.range(of: "^0x[a-fA-F0-9]{64}$", options: .regularExpression) != nil,
                  let total = item["total"] as? [String: Any],
                  let units = total["value"] as? String,
                  let amount = Decimal(string: units), amount >= .zero,
                  let url = URL(string: "https://etherscan.io/tx/\(hash)") else { return nil }
            let from = (item["from"] as? [String: Any])?["hash"] as? String
            let time = (item["timestamp"] as? String).flatMap { parser.date(from: $0) ?? alternate.date(from: $0) }
            return WalletChainActivity(id: "erc20:\(hash):\(index)", chain: .ethereum, hash: hash,
                 timestamp: time, state: .confirmed,
                 direction: from?.lowercased() == address.lowercased() ? "Отправлено" : "Получено",
                 amount: amount / Decimal(1_000_000), symbol: token.ticker, explorerURL: url)
        }
        return (native + transfers).sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
    }

    private struct SOLSignature: Decodable {
        let signature: String
        let blockTime: TimeInterval?
        let err: String?
        let confirmationStatus: String?
        private enum CodingKeys: String, CodingKey { case signature, blockTime, err, confirmationStatus }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            signature = try container.decode(String.self, forKey: .signature)
            blockTime = try container.decodeIfPresent(TimeInterval.self, forKey: .blockTime)
            // Solana `err` is a JSON object OR null, not a string.
            err = container.contains(.err) && !(try container.decodeNil(forKey: .err)) ? "error" : nil
            confirmationStatus = try container.decodeIfPresent(String.self, forKey: .confirmationStatus)
        }
    }
    private struct SOLResult: Decodable { let result: [SOLSignature]?; let error: RPCFaultLike? }
    private struct RPCFaultLike: Decodable { let code: Int; let message: String }

    private static func solana(_ address: String) async throws -> [WalletChainActivity] {
        guard address.range(of: "^[1-9A-HJ-NP-Za-km-z]{32,44}$", options: .regularExpression) != nil else { throw WalletPublicRPCError.badResponse }
        let body = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "getSignaturesForAddress", "params": [address, ["limit": 30]]])
        var lastError: Error = WalletPublicRPCError.badResponse
        for endpoint in ["https://api.mainnet-beta.solana.com", "https://solana-rpc.publicnode.com"] {
            do {
                guard let url = URL(string: endpoint) else { continue }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.httpBody = body
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: req)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count < 1_000_000 else { throw WalletPublicRPCError.badResponse }
                let result = try JSONDecoder().decode(SOLResult.self, from: data)
                guard result.error == nil, let rows = result.result else { throw WalletPublicRPCError.badResponse }
                return rows.compactMap { row in
                    guard row.signature.count >= 64, row.signature.count <= 90,
                          let url = URL(string: "https://solscan.io/tx/\(row.signature)") else { return nil }
                    let state: WalletChainActivity.State = row.err != nil ? .failed :
                        (row.confirmationStatus == "finalized" || row.confirmationStatus == "confirmed" ? .confirmed : .pending)
                    return WalletChainActivity(id: "sol:\(row.signature)", chain: .solana, hash: row.signature,
                                               timestamp: row.blockTime.map(Date.init(timeIntervalSince1970:)), state: state,
                                               direction: "Операция", amount: nil, symbol: "SOL", explorerURL: url)
                }
            } catch {
                if error is CancellationError { throw error }
                lastError = error
            }
        }
        throw lastError
    }
}

@MainActor
final class WalletActivityStore: ObservableObject {
    @Published private(set) var activity: [SpyderChain: [WalletChainActivity]] = [:]
    @Published private(set) var errors: [SpyderChain: String] = [:]
    @Published private(set) var updatedAt: [SpyderChain: Date] = [:]
    @Published private(set) var loading: Set<SpyderChain> = []
    private var generation = UUID()

    func clear() {
        generation = UUID()
        activity = [:]; errors = [:]; updatedAt = [:]; loading = []
    }

    func refresh(addresses: [SpyderAddress]) async {
        let id = generation
        await withTaskGroup(of: (SpyderChain, Result<[WalletChainActivity], Error>).self) { group in
            for address in addresses where !loading.contains(address.chain) {
                loading.insert(address.chain)
                group.addTask {
                    do { return (address.chain, .success(try await WalletActivityClient.fetch(address))) }
                    catch { return (address.chain, .failure(error)) }
                }
            }
            for await (chain, outcome) in group {
                guard id == generation else { continue }
                loading.remove(chain)
                switch outcome {
                case .success(let items):
                    activity[chain] = items; errors.removeValue(forKey: chain); updatedAt[chain] = Date()
                case .failure(let error):
                    // Keep the old list explicitly stale; don't substitute an empty transaction history.
                    errors[chain] = error.localizedDescription
                }
            }
        }
    }
    var recent: [WalletChainActivity] {
        activity.values.flatMap { $0 }.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
    }
}
