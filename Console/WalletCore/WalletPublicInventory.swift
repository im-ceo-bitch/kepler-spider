import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Untrusted discovery results are deliberately not part of the verified USD total or a signing intent.
struct WalletSPLHolding: Identifiable, Equatable, Sendable {
    let program: String; let mint: String; let decimals: Int; let raw: String; let accounts: Int; let frozenAccounts: Int
    var id: String { program + ":" + mint }
    var amount: String { WalletExactAmount.display(raw, decimals: decimals) }
    var possibleCollectible: Bool { decimals == 0 && raw == "1" }
}
struct WalletSPLInventory: Sendable {
    let owner: String; let holdings: [WalletSPLHolding]; let fetchedAt: Date
    static let programs = ["TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"]
    static let genesis = "5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d"
    static let endpoints = ["https://api.mainnet-beta.solana.com", "https://solana-rpc.publicnode.com"]
    private struct Reply: Decodable {
        struct Result: Decodable { let value: [Row]; let context: Context }
        struct Context: Decodable { let slot: UInt64 }
        struct Row: Decodable { let pubkey: String; let account: Account }
        struct Account: Decodable { let owner: String; let executable: Bool; let data: ParsedData }
        struct ParsedData: Decodable { let parsed: Parsed }
        struct Parsed: Decodable { let type: String; let info: Info }
        struct Info: Decodable { let mint: String; let owner: String; let tokenAmount: Amount; let state: String }
        struct Amount: Decodable { let amount: String; let decimals: Int }
        let jsonrpc: String; let id: String; let result: Result
    }
    static func decode(_ bytes: Data, owner: String, program: String, id: String) throws -> [WalletSPLHolding] {
        guard bytes.count <= 512_000, programs.contains(program), WalletAddressValidator.check(owner, for: .solana) == .valid else { throw WalletExpansionError.invalid }
        let root = try JSONDecoder().decode(Reply.self, from: bytes)
        guard let json = try JSONSerialization.jsonObject(with: bytes) as? [String:Any], json["error"] == nil || json["error"] is NSNull,
              root.jsonrpc == "2.0", root.id == id, root.result.context.slot > 0, root.result.value.count <= 1500 else { throw WalletExpansionError.mismatch }
        var seen = Set<String>(), groups = [String:WalletSPLHolding]()
        for row in root.result.value {
            let info = row.account.data.parsed.info, token = info.tokenAmount
            guard seen.insert(row.pubkey).inserted, WalletAddressValidator.check(row.pubkey, for: .solana) == .valid,
                  row.account.owner == program, !row.account.executable, row.account.data.parsed.type == "account", info.owner == owner,
                  WalletAddressValidator.check(info.mint, for: .solana) == .valid, ["initialized","frozen"].contains(info.state),
                  (0...36).contains(token.decimals), WalletExactAmount.valid(token.amount), UInt64(token.amount) != nil else { throw WalletExpansionError.mismatch }
            if token.amount == "0" { continue }
            let previous = groups[info.mint]
            guard previous == nil || previous?.decimals == token.decimals else { throw WalletExpansionError.mismatch }
            let amount = try WalletExactAmount.add(previous?.raw ?? "0", token.amount)
            guard UInt64(amount) != nil else { throw WalletExpansionError.mismatch }
            groups[info.mint] = .init(program: program, mint: info.mint, decimals: token.decimals, raw: amount, accounts: (previous?.accounts ?? 0)+1, frozenAccounts: (previous?.frozenAccounts ?? 0)+(info.state == "frozen" ? 1 : 0))
        }
        return groups.values.sorted { $0.id < $1.id }
    }
    private static func fetch(_ endpoint: String, method: String, id: String, params: [Any]) async throws -> Data {
        guard endpoints.contains(endpoint), let url = URL(string: endpoint) else { throw WalletExpansionError.invalid }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc":"2.0","id":id,"method":method,"params":params])
        return try await WalletExpansionHTTP.load(request)
    }
    static func load(owner: String) async throws -> Self {
        guard WalletAddressValidator.check(owner, for: .solana) == .valid else { throw WalletExpansionError.invalid }
        var last: Error = WalletExpansionError.unavailable
        for endpoint in endpoints {
            do {
                let id = UUID().uuidString
                let genesisData = try await fetch(endpoint, method: "getGenesisHash", id: id, params: [])
                guard let reply = try JSONSerialization.jsonObject(with: genesisData) as? [String:Any], reply["jsonrpc"] as? String == "2.0", reply["id"] as? String == id, reply["result"] as? String == genesis, reply["error"] == nil || reply["error"] is NSNull else { throw WalletExpansionError.wrongNetwork }
                var holdings: [WalletSPLHolding] = []
                for program in programs {
                    let id = UUID().uuidString
                    let bytes = try await fetch(endpoint, method: "getTokenAccountsByOwner", id: id, params: [owner,["programId":program],["encoding":"jsonParsed","commitment":"finalized"]])
                    holdings += try decode(bytes, owner: owner, program: program, id: id)
                }
                try Task.checkCancellation()
                return .init(owner: owner, holdings: holdings, fetchedAt: Date())
            } catch { try Task.checkCancellation(); last = error }
        }
        throw last
    }
}

struct WalletBitcoinUTXO: Identifiable, Decodable, Equatable, Sendable {
    struct Status: Decodable, Equatable, Sendable { let confirmed: Bool; let block_height: UInt64?; let block_hash: String? }
    let txid: String; let vout: UInt32; let value: UInt64; let status: Status
    var id: String { txid + ":" + String(vout) }
}
struct WalletBitcoinInventory: Sendable {
    let owner: String; let outputs: [WalletBitcoinUTXO]; let fetchedAt: Date
    var confirmed: UInt64 { outputs.filter { $0.status.confirmed }.reduce(0) { $0 + $1.value } }
    var pending: UInt64 { outputs.filter { !$0.status.confirmed }.reduce(0) { $0 + $1.value } }
    static let maxMoney: UInt64 = 2_100_000_000_000_000
    static func decode(_ bytes: Data) throws -> [WalletBitcoinUTXO] {
        guard bytes.count <= 512_000 else { throw WalletExpansionError.invalid }
        let rows = try JSONDecoder().decode([WalletBitcoinUTXO].self, from: bytes)
        var total: UInt64 = 0, seen = Set<String>()
        guard rows.count <= 5000 else { throw WalletExpansionError.invalid }
        for row in rows {
            guard row.txid.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil, seen.insert(row.id).inserted,
                  row.value > 0, row.value <= maxMoney, total <= maxMoney-row.value else { throw WalletExpansionError.mismatch }
            if row.status.confirmed {
                guard let height = row.status.block_height, height > 0, let hash = row.status.block_hash, hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw WalletExpansionError.mismatch }
            } else { guard row.status.block_height == nil, row.status.block_hash == nil else { throw WalletExpansionError.mismatch } }
            total += row.value
        }
        return rows.sorted { $0.id < $1.id }
    }
    static func load(owner: String) async throws -> Self {
        guard WalletAddressValidator.check(owner, for: .bitcoin) == .valid else { throw WalletExpansionError.invalid }
        var last: Error = WalletExpansionError.unavailable
        for host in ["https://blockstream.info/api", "https://mempool.space/api"] {
            do {
                guard let url = URL(string: host + "/address/" + owner.lowercased() + "/utxo") else { throw WalletExpansionError.invalid }
                let data = try await WalletExpansionHTTP.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12))
                let outputs = try decode(data)
                return .init(owner: owner, outputs: outputs, fetchedAt: Date())
            } catch { try Task.checkCancellation(); last = error }
        }
        throw last
    }
}

/// An allowance is read-only and explicitly scoped to a user-entered spender; not a trust verdict.
struct WalletAllowanceSnapshot: Sendable {
    let asset: WalletNetworkAsset; let owner: String; let spender: String; let raw: String; let fetchedAt: Date
    var unlimited: Bool { raw == WalletExactAmount.max }
    static func fetch(asset: WalletNetworkAsset, owner: String, spender: String, client: WalletNetworkRPCClient = .init()) async throws -> Self {
        guard WalletNetworkAsset.tokens.contains(asset), WalletAddressValidator.check(owner, for: .ethereum) == .valid,
              WalletAddressValidator.check(spender, for: .ethereum) == .valid, owner.lowercased() != spender.lowercased() else { throw WalletExpansionError.invalid }
        let data = "0xdd62ed3e" + String(repeating:"0",count:24) + owner.dropFirst(2).lowercased() + String(repeating:"0",count:24) + spender.dropFirst(2).lowercased()
        var results: [String] = []
        for endpoint in asset.network.endpoints {
            try await client.verify(asset.network, endpoint)
            let raw = try WalletExactAmount.abiWord(await client.call(endpoint, "eth_call", [["to":asset.contract,"data":data],"latest"]))
            results.append(raw)
        }
        guard results.count >= 2, let raw = results.first, results.allSatisfy({ $0 == raw }) else { throw WalletExpansionError.mismatch }
        return .init(asset: asset, owner: owner, spender: spender, raw: raw, fetchedAt: Date())
    }
}
