import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Isolated native test-ETH execution. Mainnet, arbitrary calldata and tokens are excluded.
enum WalletSepoliaTransferError: Error { case invalid, wrongChain, inconsistent, stale, busy, storage, insufficientFunds }

struct WalletSepoliaIntent: Equatable, Sendable {
    static let chainID: UInt64 = 11155111
    let sender: String
    let recipient: String
    let amount: String // canonical wei
    let nonce: UInt64
    let gas: UInt64
    let maxFee: UInt64
    let priority: UInt64
    let checkedAt: Date
    var maxCost: String { (try? WalletExactAmount.multiply(String(maxFee), by: gas)) ?? "" }
    func validate(now: Date = Date()) throws {
        guard WalletEVMUnits.isAddress(sender), WalletEVMUnits.isAddress(recipient), sender.lowercased() != recipient.lowercased(),
              WalletExactAmount.valid(amount), amount != "0", nonce <= 10_000_000_000,
              (21_000...500_000).contains(gas), (1...100_000_000_000).contains(maxFee), priority > 0, priority <= maxFee,
              !maxCost.isEmpty else { throw WalletSepoliaTransferError.invalid }
        let age = now.timeIntervalSince(checkedAt)
        guard age >= 0, age < 90 else { throw WalletSepoliaTransferError.stale }
    }
}

struct WalletSepoliaRPC: Sendable {
    static let endpoints = ["https://ethereum-sepolia-rpc.publicnode.com", "https://public.1rpc.io/sepolia"]
    typealias Transport = @Sendable (String, String, Data) async throws -> Data
    let transport: Transport
    init(transport: @escaping Transport = { endpoint, method, params in try await Self.live(endpoint, method, params) }) { self.transport = transport }
    static func live(_ endpoint: String, _ method: String, _ params: Data) async throws -> Data {
        let allowed = ["eth_chainId", "eth_getBalance", "eth_getTransactionCount", "eth_gasPrice", "eth_maxPriorityFeePerGas", "eth_estimateGas", "eth_call", "eth_sendRawTransaction", "eth_getTransactionReceipt", "eth_getBlockByNumber"]
        guard endpoints.contains(endpoint), allowed.contains(method), let url = URL(string: endpoint), let array = try JSONSerialization.jsonObject(with: params) as? [Any] else { throw WalletSepoliaTransferError.invalid }
        let id = UUID().uuidString
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc":"2.0", "id":id, "method":method, "params":array])
        let data = try await WalletExpansionHTTP.load(request)
        guard let reply = try JSONSerialization.jsonObject(with: data) as? [String:Any], reply["jsonrpc"] as? String == "2.0", reply["id"] as? String == id,
              reply["error"] == nil || reply["error"] is NSNull, let result = reply["result"] else { throw WalletSepoliaTransferError.inconsistent }
        return try JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed])
    }
    func call(_ endpoint: String, _ method: String, _ params: [Any]) async throws -> Any {
        try Task.checkCancellation()
        return try JSONSerialization.jsonObject(with: await transport(endpoint, method, JSONSerialization.data(withJSONObject: params)), options: [.fragmentsAllowed])
    }
    func string(_ endpoint: String, _ method: String, _ params: [Any]) async throws -> String {
        guard let result = try await call(endpoint, method, params) as? String else { throw WalletSepoliaTransferError.inconsistent }; return result
    }
    func quantity(_ endpoint: String, _ method: String, _ params: [Any], max: UInt64) async throws -> UInt64 {
        try WalletEVMUnits.integer(await string(endpoint, method, params), upperBound: max)
    }
    func verify(_ endpoint: String) async throws {
        guard try await quantity(endpoint, "eth_chainId", [], max: UInt64.max) == WalletSepoliaIntent.chainID else { throw WalletSepoliaTransferError.wrongChain }
    }
    func quote(sender: String, recipient: String, amount: String) async throws -> WalletSepoliaIntent {
        guard WalletEVMUnits.isAddress(sender), WalletEVMUnits.isAddress(recipient), sender.lowercased() != recipient.lowercased() else { throw WalletSepoliaTransferError.invalid }
        let wei = try WalletExactAmount.parse(amount, decimals: 18)
        guard wei != "0" else { throw WalletSepoliaTransferError.invalid }
        let start = Date(), tx = ["from":sender, "to":recipient, "value":try WalletEVMUnits.hexFromDecimal(wei), "data":"0x"]
        struct Sample: Sendable { let balance: String; let nonce: UInt64; let gas: UInt64; let price: UInt64; let priority: UInt64 }
        let samples = try await withThrowingTaskGroup(of: Sample.self) { group in
            for endpoint in Self.endpoints { group.addTask {
                try await verify(endpoint)
                async let balance = WalletExactAmount.fromHex(string(endpoint, "eth_getBalance", [sender,"pending"]))
                async let nonce = quantity(endpoint, "eth_getTransactionCount", [sender,"pending"], max: 10_000_000_000)
                async let gas = quantity(endpoint, "eth_estimateGas", [tx], max: 400_000)
                async let price = quantity(endpoint, "eth_gasPrice", [], max: 50_000_000_000)
                async let priority = quantity(endpoint, "eth_maxPriorityFeePerGas", [], max: 50_000_000_000)
                let sample = try await Sample(balance: balance, nonce: nonce, gas: gas, price: price, priority: priority)
                try WalletEVMUnits.validateSimulation(await string(endpoint, "eth_call", [tx,"pending"]), asset: .eth)
                try await verify(endpoint)
                return sample
            } }
            var result: [Sample] = []; for try await value in group { result.append(value) }; return result
        }
        guard samples.count == 2, samples[0].nonce == samples[1].nonce, let gas = samples.map(\.gas).max(), gas >= 21_000,
              samples.allSatisfy({ $0.gas >= 21_000 && $0.price > 0 && $0.priority > 0 }), let price = samples.map(\.price).max(), let priority = samples.map(\.priority).max() else { throw WalletSepoliaTransferError.inconsistent }
        let intent = WalletSepoliaIntent(sender: sender, recipient: recipient, amount: wei, nonce: samples[0].nonce, gas: gas + gas/5, maxFee: max(price*2, priority), priority: priority, checkedAt: start)
        try intent.validate()
        let total = try WalletExactAmount.add(wei, intent.maxCost)
        guard samples.allSatisfy({ WalletExactAmount.compare($0.balance,total) >= 0 }) else { throw WalletSepoliaTransferError.insufficientFunds }
        return intent
    }
    /// Check both chains and pending nonces again before publication. No retry across endpoints.
    func revalidate(_ intent: WalletSepoliaIntent) async throws {
        try intent.validate()
        let fresh = try await quote(sender: intent.sender, recipient: intent.recipient, amount: WalletExactAmount.display(intent.amount, decimals: 18))
        guard fresh.nonce == intent.nonce, fresh.gas <= intent.gas, fresh.maxFee <= intent.maxFee, fresh.priority <= intent.priority else { throw WalletSepoliaTransferError.stale }
        try intent.validate()
    }
    func finalStatus(hash: String) async throws -> WalletSepoliaRecord.Status? {
        guard WalletSepoliaRecord.validHash(hash) else { throw WalletSepoliaTransferError.invalid }
        var results: [String] = []
        for endpoint in Self.endpoints {
            try await verify(endpoint)
            let reply = try await call(endpoint, "eth_getTransactionReceipt", [hash])
            if reply is NSNull { return nil }
            guard let receipt = reply as? [String:Any], let h = receipt["transactionHash"] as? String, h.lowercased() == hash.lowercased(),
                  let bh = receipt["blockHash"] as? String, WalletSepoliaRecord.validHash(bh), let bn = receipt["blockNumber"] as? String,
                  let status = receipt["status"] as? String, ["0x0","0x1"].contains(status),
                  let block = try await call(endpoint, "eth_getBlockByNumber", [bn,false]) as? [String:Any], (block["hash"] as? String)?.lowercased() == bh.lowercased(), block["number"] as? String == bn,
                  let final = try await call(endpoint, "eth_getBlockByNumber", ["finalized",false]) as? [String:Any], let height = final["number"] as? String else { throw WalletSepoliaTransferError.inconsistent }
            let mined = try WalletEVMUnits.integer(bn, upperBound: UInt64.max), finalized = try WalletEVMUnits.integer(height, upperBound: UInt64.max)
            if finalized < mined { return nil }
            try await verify(endpoint)
            results.append("\(bh.lowercased()):\(bn):\(status)")
        }
        guard results.count == 2, results[0] == results[1] else { throw WalletSepoliaTransferError.inconsistent }
        return results[0].hasSuffix(":0x1") ? .finalized : .reverted
    }
}

struct WalletSepoliaRecord: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable { case unknown, submitted, finalized, reverted }
    let sender: String; let recipient: String; let amount: String; let nonce: UInt64; let hash: String; let created: Date
    var status: Status
    var id: String { hash }
    static func validHash(_ value: String) -> Bool { value.range(of: "^0x[0-9a-fA-F]{64}$", options: .regularExpression) != nil }
    var valid: Bool { WalletEVMUnits.isAddress(sender) && WalletEVMUnits.isAddress(recipient) && sender.lowercased() != recipient.lowercased() && WalletExactAmount.valid(amount) && amount != "0" && nonce <= 10_000_000_000 && Self.validHash(hash) }
}

/// Single application-process journal. Stores only public transaction metadata, never signed bytes.
actor WalletSepoliaJournal {
    private let file: URL
    private var records: [WalletSepoliaRecord]
    static let shared: Result<WalletSepoliaJournal, Error> = Result {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return try WalletSepoliaJournal(file: root.appendingPathComponent("SpyderSepolia", isDirectory: true).appendingPathComponent("transactions-v1.json"))
    }
    init(file: URL) throws {
        self.file = file
        if FileManager.default.fileExists(atPath: file.path) {
            let data = try Data(contentsOf: file)
            guard data.count <= 2_000_000 else { throw WalletSepoliaTransferError.storage }
            let decoded = try JSONDecoder().decode([WalletSepoliaRecord].self, from: data)
            guard decoded.count <= 4000, decoded.allSatisfy(\.valid), Set(decoded.map { $0.hash.lowercased() }).count == decoded.count,
                  Set(decoded.map { "\($0.sender.lowercased()):\($0.nonce)" }).count == decoded.count else { throw WalletSepoliaTransferError.storage }
            records = decoded
        } else { records = [] }
    }
    private func save(_ next: [WalletSepoliaRecord]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        var dir = file.deletingLastPathComponent(); var values = URLResourceValues(); values.isExcludedFromBackup = true; try dir.setResourceValues(values)
        try JSONEncoder().encode(next).write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try JSONEncoder().encode(next).write(to: file, options: .atomic)
        #endif
        records = next
    }
    func reserve(_ record: WalletSepoliaRecord) throws {
        guard record.valid, record.status == .unknown, records.count < 4000, !records.contains(where: { $0.hash.lowercased() == record.hash.lowercased() || ($0.sender.lowercased() == record.sender.lowercased() && ($0.nonce == record.nonce || $0.status == .unknown || $0.status == .submitted)) }) else { throw WalletSepoliaTransferError.busy }
        try save(records + [record])
    }
    func all(sender: String) -> [WalletSepoliaRecord] { records.filter { $0.sender.lowercased() == sender.lowercased() }.sorted { $0.created > $1.created } }
    func mark(hash: String, status: WalletSepoliaRecord.Status) throws {
        guard let i = records.firstIndex(where: { $0.hash == hash }), status != .unknown else { throw WalletSepoliaTransferError.invalid }
        guard records[i].status == .unknown || records[i].status == .submitted else { return }
        var next = records; next[i].status = status; try save(next)
    }
    func refresh(sender: String, rpc: WalletSepoliaRPC = .init()) async throws {
        for row in all(sender: sender) where row.status == .unknown || row.status == .submitted {
            if let status = try await rpc.finalStatus(hash: row.hash) { try mark(hash: row.hash, status: status) }
        }
    }
}
