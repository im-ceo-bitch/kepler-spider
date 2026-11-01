import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Block 7, Stage 5. READ-ONLY reconciliation of an OUTGOING EIP-1559 transaction.
// The transaction hash must correspond to an already approved, immutable intent.
// This file cannot sign, broadcast, access Keychain, or display a success based on a provider's claim alone.
struct WalletEVMOutgoingEvidence: Equatable {
    let txHash: String
    let sender: String
    let recipient: String
    let asset: WalletEVMAsset
    let amountBaseUnits: String
    let nonce: UInt64
    let blockNumber: UInt64
    let blockHash: String
    let confirmations: UInt64
    let succeeded: Bool
}

enum WalletEVMOutgoingAssessment: Equatable {
    case notSeen
    case pending(providers: Int)
    case observed(WalletEVMOutgoingEvidence, providers: Int)
    case confirmed(WalletEVMOutgoingEvidence)
    case reverted(WalletEVMOutgoingEvidence)
}

enum WalletEVMOutgoingError: LocalizedError, Equatable {
    case invalidHash, invalidIntent, wrongNetwork, mismatchedTransaction, inconsistentProviders, rpc
    var errorDescription: String? {
        switch self {
        case .invalidHash: "Неверный хеш Ethereum-транзакции."
        case .invalidIntent: "Данные отправленного перевода не подтверждены."
        case .wrongNetwork: "RPC не подтвердил сеть Ethereum Mainnet."
        case .mismatchedTransaction: "Транзакция отличается от подтверждённых реквизитов перевода."
        case .inconsistentProviders: "Ethereum RPC сообщают противоречивые сведения."
        case .rpc: "Не удалось проверить исходящий перевод через Ethereum RPC."
        }
    }
}

struct WalletEVMOutgoingTracker {
    typealias Transport = (URL, String, [Any]) async throws -> Any?
    private let endpoints: [URL]
    private let transport: Transport
    static let confirmationsRequired: UInt64 = 12
    private static let transferTopic = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

    init(endpoints: [URL] = [URL(string: "https://ethereum-rpc.publicnode.com")!, URL(string: "https://cloudflare-eth.com")!],
         transport: @escaping Transport = WalletEVMOutgoingTracker.fetchRPC) {
        var seenHosts = Set<String>()
        var unique: [URL] = []
        for endpoint in endpoints {
            guard endpoint.scheme?.lowercased() == "https", let host = endpoint.host?.lowercased(),
                  seenHosts.insert(host).inserted else { continue }
            unique.append(endpoint)
            if unique.count == 3 { break }
        }
        self.endpoints = unique
        self.transport = transport
    }

    func reconcile(txHash: String, intent: WalletEVMUnsignedIntent) async throws -> WalletEVMOutgoingAssessment {
        guard Self.isHash(txHash) else { throw WalletEVMOutgoingError.invalidHash }
        guard WalletEVMUnits.isAddress(intent.sender), WalletEVMUnits.isAddress(intent.recipient),
              intent.sender.caseInsensitiveCompare(intent.recipient) != .orderedSame,
              (21_000...10_000_000).contains(intent.gasLimit), intent.maxFeePerGas > 0,
              intent.priorityFeePerGas > 0, intent.priorityFeePerGas <= intent.maxFeePerGas,
              !endpoints.isEmpty else { throw WalletEVMOutgoingError.invalidIntent }

        var observations: [WalletEVMOutgoingEvidence] = []
        var pending = 0
        var unseen = 0
        var errors: [WalletEVMOutgoingError] = []
        for endpoint in endpoints {
            do {
                switch try await inspect(endpoint, txHash: txHash, intent: intent) {
                case .notSeen: unseen += 1
                case .pending: pending += 1
                case .observed(let entry): observations.append(entry)
                }
            } catch is CancellationError { throw CancellationError() }
            catch let error as WalletEVMOutgoingError { errors.append(error) }
            catch { errors.append(.rpc) }
        }
        if errors.contains(where: { $0 != .rpc }) { throw WalletEVMOutgoingError.inconsistentProviders }
        if let first = observations.first {
            for next in observations.dropFirst() {
                guard first.blockHash.caseInsensitiveCompare(next.blockHash) == .orderedSame,
                      first.blockNumber == next.blockNumber,
                      first.succeeded == next.succeeded,
                      first.nonce == next.nonce else { throw WalletEVMOutgoingError.inconsistentProviders }
            }
            let lowest = observations.map(\.confirmations).min() ?? 0
            let evidence = WalletEVMOutgoingEvidence(txHash: first.txHash, sender: first.sender,
                recipient: first.recipient, asset: first.asset, amountBaseUnits: first.amountBaseUnits,
                nonce: first.nonce, blockNumber: first.blockNumber, blockHash: first.blockHash,
                confirmations: lowest, succeeded: first.succeeded)
            // Two consistent RPC answers and 12 confirmations are necessary for a final UI status.
            if observations.count >= 2 && lowest >= Self.confirmationsRequired {
                return evidence.succeeded ? .confirmed(evidence) : .reverted(evidence)
            }
            return .observed(evidence, providers: observations.count)
        }
        if pending > 0 { return .pending(providers: pending) }
        if unseen == endpoints.count { return .notSeen }
        throw WalletEVMOutgoingError.rpc
    }

    private enum Observation { case notSeen, pending, observed(WalletEVMOutgoingEvidence) }

    private func inspect(_ endpoint: URL, txHash: String, intent: WalletEVMUnsignedIntent) async throws -> Observation {
        guard Self.quantity(try await string(endpoint, "eth_chainId", [])) == 1 else {
            throw WalletEVMOutgoingError.wrongNetwork
        }
        guard let txAny = try await transport(endpoint, "eth_getTransactionByHash", [txHash]) else { return .notSeen }
        guard let tx = txAny as? [String: Any],
              let actualHash = tx["hash"] as? String, Self.same(actualHash, txHash),
              let from = tx["from"] as? String, Self.same(from, intent.sender),
              let to = tx["to"] as? String, Self.same(to, intent.transactionTarget),
              let txType = tx["type"] as? String, Self.quantity(txType) == 2,
              let chain = tx["chainId"] as? String, Self.quantity(chain) == 1,
              let nonceHex = tx["nonce"] as? String, Self.quantity(nonceHex) == intent.nonce,
              let gas = tx["gas"] as? String, Self.quantity(gas) == intent.gasLimit,
              let fee = tx["maxFeePerGas"] as? String, Self.quantity(fee) == intent.maxFeePerGas,
              let priority = tx["maxPriorityFeePerGas"] as? String, Self.quantity(priority) == intent.priorityFeePerGas,
              let value = tx["value"] as? String,
              let expectedValue = try? WalletEVMUnits.hexFromDecimal(intent.asset == .eth ? intent.baseUnits : "0"),
              Self.quantityStringEquals(value, expectedValue),
              let input = tx["input"] as? String,
              Self.same(input, intent.tokenCallData ?? "0x") else {
            throw WalletEVMOutgoingError.mismatchedTransaction
        }
        guard let receiptAny = try await transport(endpoint, "eth_getTransactionReceipt", [txHash]) else { return .pending }
        guard let receipt = receiptAny as? [String: Any],
              let receiptHash = receipt["transactionHash"] as? String, Self.same(receiptHash, txHash),
              let receiptFrom = receipt["from"] as? String, Self.same(receiptFrom, intent.sender),
              let receiptTo = receipt["to"] as? String, Self.same(receiptTo, intent.transactionTarget),
              let status = receipt["status"] as? String, let statusCode = Self.quantity(status), statusCode <= 1,
              let blockNumber = receipt["blockNumber"] as? String, let mined = Self.quantity(blockNumber),
              let blockHash = receipt["blockHash"] as? String, Self.isHash(blockHash),
              let txBlockHash = tx["blockHash"] as? String, Self.same(txBlockHash, blockHash),
              let txBlockNumber = tx["blockNumber"] as? String, Self.quantity(txBlockNumber) == mined else {
            throw WalletEVMOutgoingError.inconsistentProviders
        }
        guard let canonical = try await transport(endpoint, "eth_getBlockByNumber", [blockNumber, false]) as? [String: Any],
              let canonicalHash = canonical["hash"] as? String, Self.same(canonicalHash, blockHash),
              let head = Self.quantity(try await string(endpoint, "eth_blockNumber", [])), head >= mined else {
            throw WalletEVMOutgoingError.inconsistentProviders
        }
        // ERC-20 success must prove the actual token transfer, not merely successful execution.
        if statusCode == 1 && intent.asset != .eth {
            guard let logs = receipt["logs"] as? [[String: Any]],
                  let expectedData = try? WalletEVMUnits.hexFromDecimal(intent.baseUnits),
                  logs.contains(where: { log in
                    guard let contract = log["address"] as? String, Self.same(contract, intent.transactionTarget),
                          (log["removed"] as? Bool) != true,
                          let topics = log["topics"] as? [String], topics.count == 3,
                          Self.same(topics[0], Self.transferTopic),
                          Self.same(topics[1], Self.addressTopic(intent.sender)),
                          Self.same(topics[2], Self.addressTopic(intent.recipient)),
                          let logData = log["data"] as? String,
                          logData.count == 66, Self.quantityStringEquals(logData, expectedData) else { return false }
                    if let logHash = log["transactionHash"] as? String { return Self.same(logHash, txHash) }
                    return true
                  }) else { throw WalletEVMOutgoingError.mismatchedTransaction }
        }
        return .observed(WalletEVMOutgoingEvidence(txHash: txHash.lowercased(), sender: intent.sender,
            recipient: intent.recipient, asset: intent.asset, amountBaseUnits: intent.baseUnits,
            nonce: intent.nonce, blockNumber: mined, blockHash: blockHash.lowercased(),
            confirmations: head - mined + 1, succeeded: statusCode == 1))
    }

    private static func isHash(_ value: String) -> Bool {
        value.range(of: "^0x[0-9a-fA-F]{64}$", options: .regularExpression) != nil
    }
    private static func same(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }
    private static func addressTopic(_ address: String) -> String {
        "0x" + String(repeating: "0", count: 24) + String(address.dropFirst(2)).lowercased()
    }
    private static func quantity(_ value: String) -> UInt64? {
        guard value.range(of: "^0x(0|[1-9a-fA-F][0-9a-fA-F]*)$", options: .regularExpression) != nil else { return nil }
        return UInt64(value.dropFirst(2), radix: 16)
    }
    private static func quantityStringEquals(_ a: String, _ b: String) -> Bool {
        // Quantity is at most UInt256: normalise arbitrary-sized hex without using Float/Decimal.
        func norm(_ v: String) -> String? {
            guard v.hasPrefix("0x"), v.count <= 66,
                  v.dropFirst(2).utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
            let digits = v.dropFirst(2).lowercased().drop(while: { $0 == "0" })
            return digits.isEmpty ? "0" : String(digits)
        }
        guard let lhs = norm(a), let rhs = norm(b) else { return false }
        return lhs == rhs
    }
    private func string(_ url: URL, _ method: String, _ params: [Any]) async throws -> String {
        guard let value = try await transport(url, method, params) as? String else { throw WalletEVMOutgoingError.rpc }
        return value
    }
    private static func fetchRPC(_ endpoint: URL, _ method: String, _ params: [Any]) async throws -> Any? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 57, "method": method, "params": params])
        let (bytes, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), bytes.count <= 65_536,
              let body = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              body["jsonrpc"] as? String == "2.0", body["id"] as? Int == 57,
              body["error"] == nil, let value = body["result"] else { throw WalletEVMOutgoingError.rpc }
        return value is NSNull ? nil : value
    }
}
