import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Block 7 / Stage 4. Independent READ-ONLY verification of an ERC-20 deposit.
// A transaction shown by a block explorer is NOT sufficient proof of receipt.
// No seed phrase, private key, signer, or broadcast RPC is used here.
struct WalletEVMDepositEvidence: Equatable {
    let hash: String
    let token: WalletEVMAsset
    let recipient: String
    let blockNumber: UInt64
    let blockHash: String
    let confirmations: UInt64
    let amountBaseUnits: String
    var amountText: String { WalletEVMDepositVerifier.formatTokenUnits(amountBaseUnits) }
}

enum WalletEVMDepositAssessment: Equatable {
    case notMined
    case observed(WalletEVMDepositEvidence, providers: Int)
    case independentlyConfirmed(WalletEVMDepositEvidence)
}

enum WalletEVMDepositError: LocalizedError {
    case input, unsupportedAsset, rpc, wrongNetwork, failedTransaction, noMatchingTransfer, inconsistentProviders
    var errorDescription: String? {
        switch self {
        case .input: "Неправильный адрес Ethereum или хеш транзакции."
        case .unsupportedAsset: "Проверка поддерживает только USDT/USDC ERC-20 Ethereum."
        case .rpc: "Не удалось проверить транзакцию через Ethereum RPC."
        case .wrongNetwork: "RPC не подтвердил Ethereum Mainnet (chainId 1)."
        case .failedTransaction: "Транзакция завершилась ошибкой и не зачислила токены."
        case .noMatchingTransfer: "В транзакции нет поступления выбранного токена на ваш адрес."
        case .inconsistentProviders: "Ethereum RPC-провайдеры расходятся. Подтверждение невозможно."
        }
    }
}

struct WalletEVMDepositVerifier {
    typealias Transport = (URL, String, [Any]) async throws -> Any?
    private let endpoints: [URL]
    private let transport: Transport
    private static let transferTopic = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
    private static let requiredConfirmations: UInt64 = 12

    init(endpoints: [URL] = [URL(string: "https://ethereum-rpc.publicnode.com")!, URL(string: "https://cloudflare-eth.com")!],
         transport: @escaping Transport = WalletEVMDepositVerifier.fetchRPC) {
        self.endpoints = Array(endpoints.filter { $0.scheme?.lowercased() == "https" }.prefix(3))
        self.transport = transport
    }

    func verify(txHash: String, recipient: String, token: WalletEVMAsset) async throws -> WalletEVMDepositAssessment {
        guard token == .usdt || token == .usdc, let contract = token.contract else {
            throw WalletEVMDepositError.unsupportedAsset
        }
        guard Self.isHash(txHash), WalletEVMUnits.isAddress(recipient), !endpoints.isEmpty else {
            throw WalletEVMDepositError.input
        }
        var evidence: [WalletEVMDepositEvidence] = []
        var notMined = 0
        var errors: [WalletEVMDepositError] = []
        for url in endpoints {
            do {
                if let row = try await verifyOnProvider(url, txHash: txHash, recipient: recipient, token: token, contract: contract) {
                    evidence.append(row)
                } else { notMined += 1 }
            } catch is CancellationError { throw CancellationError() }
            catch let error as WalletEVMDepositError { errors.append(error) }
            catch { errors.append(.rpc) }
        }
        if let first = evidence.first {
            // A mismatch MUST NOT be silently replaced by a successful provider.
            guard !errors.contains(.wrongNetwork), !errors.contains(.failedTransaction),
                  !errors.contains(.noMatchingTransfer), !errors.contains(.inconsistentProviders) else { throw WalletEVMDepositError.inconsistentProviders }
            for other in evidence.dropFirst() {
                guard first.blockHash.caseInsensitiveCompare(other.blockHash) == .orderedSame,
                      first.blockNumber == other.blockNumber,
                      first.amountBaseUnits == other.amountBaseUnits else {
                    throw WalletEVMDepositError.inconsistentProviders
                }
            }
            let minConfirmations = evidence.map(\.confirmations).min() ?? 0
            let conservative = WalletEVMDepositEvidence(hash: first.hash, token: first.token,
                recipient: first.recipient, blockNumber: first.blockNumber, blockHash: first.blockHash,
                confirmations: minConfirmations, amountBaseUnits: first.amountBaseUnits)
            // Requires two INDEPENDENT RPC answers and at least 12 blocks.
            if evidence.count >= 2 && minConfirmations >= Self.requiredConfirmations {
                return .independentlyConfirmed(conservative)
            }
            return .observed(conservative, providers: evidence.count)
        }
        if notMined == endpoints.count { return .notMined }
        if let reason = errors.first(where: { $0 != .rpc }) { throw reason }
        throw WalletEVMDepositError.rpc
    }

    private func verifyOnProvider(_ url: URL, txHash: String, recipient: String,
                                  token: WalletEVMAsset, contract: String) async throws -> WalletEVMDepositEvidence? {
        let chain = try await rpcString(url, "eth_chainId", [])
        guard chain == "0x1" else { throw WalletEVMDepositError.wrongNetwork }
        guard let receiptValue = try await transport(url, "eth_getTransactionReceipt", [txHash]) else { return nil }
        guard let receipt = receiptValue as? [String: Any],
              let actualHash = receipt["transactionHash"] as? String,
              actualHash.caseInsensitiveCompare(txHash) == .orderedSame,
              let blockHash = receipt["blockHash"] as? String, Self.isHash(blockHash),
              let blockHex = receipt["blockNumber"] as? String,
              let minedAt = Self.quantity(blockHex),
              let status = receipt["status"] as? String else { throw WalletEVMDepositError.rpc }
        guard status == "0x1" else { throw WalletEVMDepositError.failedTransaction }
        let canonicalValue = try await transport(url, "eth_getBlockByNumber", [blockHex, false])
        guard let canonical = canonicalValue as? [String: Any],
              let canonicalHash = canonical["hash"] as? String,
              canonicalHash.caseInsensitiveCompare(blockHash) == .orderedSame else {
            throw WalletEVMDepositError.inconsistentProviders
        }
        guard let logs = receipt["logs"] as? [[String: Any]] else { throw WalletEVMDepositError.rpc }
        var total = "0"
        var matching = 0
        for event in logs {
            guard (event["address"] as? String)?.caseInsensitiveCompare(contract) == .orderedSame,
                  (event["removed"] as? Bool) != true,
                  let topics = event["topics"] as? [String], topics.count == 3,
                  topics[0].lowercased() == Self.transferTopic,
                  Self.indexedAddress(topics[1]) != nil,
                  Self.indexedAddress(topics[2])?.caseInsensitiveCompare(recipient) == .orderedSame,
                  let hex = event["data"] as? String, hex.count == 66,
                  let units = Self.base10(hex) else { continue }
            // Receipts are scoped to a single transaction. Reject foreign log hashes.
            if let logHash = event["transactionHash"] as? String,
               logHash.caseInsensitiveCompare(txHash) != .orderedSame { continue }
            total = Self.addDecimal(total, units)
            matching += 1
        }
        guard matching > 0, total != "0" else { throw WalletEVMDepositError.noMatchingTransfer }
        let head = Self.quantity(try await rpcString(url, "eth_blockNumber", []))
        guard let head, head >= minedAt else { throw WalletEVMDepositError.rpc }
        return WalletEVMDepositEvidence(hash: txHash.lowercased(), token: token, recipient: recipient,
            blockNumber: minedAt, blockHash: blockHash.lowercased(),
            confirmations: head - minedAt + 1, amountBaseUnits: total)
    }

    private func rpcString(_ url: URL, _ method: String, _ params: [Any]) async throws -> String {
        guard let value = try await transport(url, method, params) as? String else { throw WalletEVMDepositError.rpc }
        return value
    }

    private static func fetchRPC(_ url: URL, _ method: String, _ params: [Any]) async throws -> Any? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 49, "method": method, "params": params])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), data.count < 65_536,
              let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              body["jsonrpc"] as? String == "2.0", body["id"] as? Int == 49,
              body["error"] == nil, let result = body["result"] else { throw WalletEVMDepositError.rpc }
        return result is NSNull ? nil : result
    }

    private static func isHash(_ value: String) -> Bool {
        value.range(of: "^0x[0-9a-fA-F]{64}$", options: .regularExpression) != nil
    }

    private static func indexedAddress(_ topic: String) -> String? {
        guard isHash(topic), topic.dropFirst(2).prefix(24).allSatisfy({ $0 == "0" }) else { return nil }
        return "0x" + String(topic.suffix(40))
    }

    private static func quantity(_ value: String) -> UInt64? {
        guard value.range(of: "^0x(0|[1-9a-fA-F][0-9a-fA-F]*)$", options: .regularExpression) != nil else { return nil }
        return UInt64(value.dropFirst(2), radix: 16)
    }

    // Decode the full uint256 without loss or floating point.
    private static func base10(_ value: String) -> String? {
        guard value.range(of: "^0x[0-9a-fA-F]{64}$", options: .regularExpression) != nil else { return nil }
        var digits: [Int] = [0]
        for c in value.dropFirst(2) {
            guard let n = c.hexDigitValue else { return nil }
            var carry = n
            for i in digits.indices {
                let next = digits[i] * 16 + carry
                digits[i] = next % 10
                carry = next / 10
            }
            while carry > 0 { digits.append(carry % 10); carry /= 10 }
        }
        return digits.reversed().map(String.init).joined()
    }

    private static func addDecimal(_ a: String, _ b: String) -> String {
        let aDigits = Array(a.utf8.reversed()), bDigits = Array(b.utf8.reversed())
        var output = "", carry = 0
        for i in 0..<max(aDigits.count, bDigits.count) {
            let left = i < aDigits.count ? Int(aDigits[i] - 48) : 0
            let right = i < bDigits.count ? Int(bDigits[i] - 48) : 0
            let total = left + right + carry
            output.append(Character(String(total % 10)))
            carry = total / 10
        }
        if carry != 0 { output.append("1") }
        return String(output.reversed())
    }

    static func formatTokenUnits(_ units: String) -> String {
        let padded = String(repeating: "0", count: max(0, 7 - units.count)) + units
        let whole = String(padded.dropLast(6))
        let fraction = String(padded.suffix(6)).reversed().drop(while: { $0 == "0" })
        let fractional = String(fraction.reversed())
        return fractional.isEmpty ? whole : whole + "." + fractional
    }
}
