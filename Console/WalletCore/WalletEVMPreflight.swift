import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Block 7, stage 1: READ-ONLY Ethereum mainnet preflight.
// Nothing in this file has access to seed words, private keys or an RPC broadcast method.
// A quote is informational and MUST NOT be treated as an authorization to send.
enum WalletEVMAsset: String, CaseIterable, Identifiable {
    case eth = "ETH", usdt = "USDT", usdc = "USDC"
    var id: String { rawValue }
    var decimals: Int { self == .eth ? 18 : 6 }
    var contract: String? {
        switch self {
        case .eth: nil
        case .usdt: "0xdAC17F958D2ee523a2206206994597C13D831ec7"
        case .usdc: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
        }
    }
}

enum WalletEVMPreflightError: LocalizedError {
    case address, amount, rpc(String), wrongChain, insufficientETH, insufficientTokens, estimate, feeTooLarge
    var errorDescription: String? {
        switch self {
        case .address: "Проверьте Ethereum-адрес отправителя и получателя."
        case .amount: "Некорректная сумма или точность токена."
        case .rpc(let message): "Ethereum RPC: \(message)"
        case .wrongChain: "Провайдер не подтвердил Ethereum Mainnet (chainId 1)."
        case .insufficientETH: "Недостаточно ETH для суммы и максимальной комиссии."
        case .insufficientTokens: "Недостаточно токенов на адресе."
        case .estimate: "Не удалось надёжно оценить gas для перевода."
        case .feeTooLarge: "Сетевая комиссия выходит за безопасные пределы расчёта."
        }
    }
}

/// Exact base-unit encoding: no Double conversion, rounding or scientific notation.
enum WalletEVMUnits {
    static func baseUnits(_ entered: String, decimals: Int) throws -> String {
        guard (0...18).contains(decimals) else { throw WalletEVMPreflightError.amount }
        let value = entered.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard value.range(of: "^[0-9]{1,12}(\\.[0-9]{1,18})?$", options: .regularExpression) != nil else {
            throw WalletEVMPreflightError.amount
        }
        let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
        let fraction = pieces.count == 2 ? String(pieces[1]) : ""
        guard fraction.count <= decimals else { throw WalletEVMPreflightError.amount }
        let joined = String(pieces[0]) + fraction + String(repeating: "0", count: decimals - fraction.count)
        let normalized = stripZeros(joined)
        guard normalized != "0" else { throw WalletEVMPreflightError.amount }
        return normalized
    }

    static func stripZeros(_ value: String) -> String {
        let remaining = value.drop(while: { $0 == "0" })
        return remaining.isEmpty ? "0" : String(remaining)
    }

    static func hexFromDecimal(_ digits: String) throws -> String {
        guard !digits.isEmpty, digits.count <= 78, digits.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            throw WalletEVMPreflightError.amount
        }
        var number = stripZeros(digits)
        if number == "0" { return "0x0" }
        var reversed = ""
        let hexAlphabet = Array("0123456789abcdef")
        while number != "0" {
            var quotient = ""
            var carry = 0
            for digit in number.utf8 {
                let current = carry * 10 + Int(digit - 48)
                let q = current / 16
                carry = current % 16
                if !quotient.isEmpty || q != 0 { quotient.append(Character(String(q))) }
            }
            reversed.append(hexAlphabet[carry])
            number = quotient.isEmpty ? "0" : quotient
        }
        return "0x" + String(reversed.reversed())
    }

    // Capped RPC quantities are used for nonce/gas/fee. Reject excessive or malformed data.
    static func integer(_ hex: String, upperBound: UInt64) throws -> UInt64 {
        guard hex.hasPrefix("0x"), hex.count > 2, hex.count <= 18 else { throw WalletEVMPreflightError.estimate }
        guard let number = UInt64(hex.dropFirst(2), radix: 16), number <= upperBound else {
            throw WalletEVMPreflightError.estimate
        }
        return number
    }

    static func decimalFromHex(_ hex: String) throws -> Decimal {
        guard hex.hasPrefix("0x"), (3...66).contains(hex.count) else { throw WalletEVMPreflightError.estimate }
        let digits = hex.dropFirst(2).drop(while: { $0 == "0" })
        // A standard ERC-20 eth_call result is 32 bytes even when the value is tiny.
        // Reject huge, unsupported quantities rather than let Decimal silently round.
        guard digits.count <= 30 else { throw WalletEVMPreflightError.estimate }
        var value = Decimal.zero
        for digit in digits {
            guard let n = digit.hexDigitValue else { throw WalletEVMPreflightError.estimate }
            value = value * 16 + Decimal(n)
        }
        return value
    }

    static func decimal(_ digits: String) throws -> Decimal {
        guard digits.count <= 30, let result = Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX")) else {
            throw WalletEVMPreflightError.amount
        }
        return result
    }

    static let weiPerETH = Decimal(string: "1000000000000000000", locale: Locale(identifier: "en_US_POSIX"))!

    static func ethString(_ amountWei: Decimal) -> String {
        let result = NSDecimalNumber(decimal: amountWei / weiPerETH)
        return result.stringValue
    }

    static func transferData(to recipient: String, baseUnits: String) throws -> String {
        guard isAddress(recipient) else { throw WalletEVMPreflightError.address }
        let encodedAmount = String(try hexFromDecimal(baseUnits).dropFirst(2))
        guard encodedAmount.count <= 64 else { throw WalletEVMPreflightError.amount }
        let address = String(recipient.dropFirst(2)).lowercased()
        return "0xa9059cbb" + String(repeating: "0", count: 24) + address +
            String(repeating: "0", count: 64 - encodedAmount.count) + encodedAmount
    }

    static func isAddress(_ value: String) -> Bool {
        value.range(of: "^0x[0-9a-fA-F]{40}$", options: .regularExpression) != nil
    }
}

struct WalletEVMQuote: Equatable {
    let asset: WalletEVMAsset
    let sender: String
    let recipient: String
    let amount: String
    let nonce: UInt64
    let gasLimit: UInt64
    let maxFeePerGas: UInt64
    let priorityFeePerGas: UInt64
    let maxFeeETH: String
    let provider: String
    let checkedAt: Date

    func matches(sender: String, recipient: String, amount: String, asset: WalletEVMAsset) -> Bool {
        self.sender.caseInsensitiveCompare(sender) == .orderedSame &&
        self.recipient.caseInsensitiveCompare(recipient) == .orderedSame &&
        self.amount == amount && self.asset == asset && Date().timeIntervalSince(checkedAt) < 45
    }
}

/// Avoids cross-provider nonce/fee mismatches: all RPC calls in one quote use the same host.
/// Every response has an independently checked JSON-RPC id and chainId.
struct WalletEVMPreflightClient {
    private let endpoints: [URL]
    private let session: URLSession
    init(endpoints: [URL] = [URL(string: "https://ethereum-rpc.publicnode.com")!, URL(string: "https://cloudflare-eth.com")!],
         session: URLSession = .shared) {
        self.endpoints = endpoints.filter { $0.scheme == "https" }
        self.session = session
    }

    func quote(sender: String, recipient: String, amount: String, asset: WalletEVMAsset) async throws -> WalletEVMQuote {
        guard WalletEVMUnits.isAddress(sender), WalletEVMUnits.isAddress(recipient),
              sender.caseInsensitiveCompare(recipient) != .orderedSame else { throw WalletEVMPreflightError.address }
        let baseUnits = try WalletEVMUnits.baseUnits(amount, decimals: asset.decimals)
        var last: Error = WalletEVMPreflightError.rpc("Нет доступного провайдера")
        for url in endpoints {
            do { return try await quote(url: url, sender: sender, recipient: recipient, amount: amount, units: baseUnits, asset: asset) }
            catch {
                if error is CancellationError { throw error }
                if case WalletEVMPreflightError.wrongChain = error { throw error }
                if case WalletEVMPreflightError.insufficientETH = error { throw error }
                if case WalletEVMPreflightError.insufficientTokens = error { throw error }
                last = error
            }
        }
        throw last
    }

    private func quote(url: URL, sender: String, recipient: String, amount: String, units: String, asset: WalletEVMAsset) async throws -> WalletEVMQuote {
        let chain = try await quantity(url, "eth_chainId", [], max: 1_000_000_000)
        guard chain == 1 else { throw WalletEVMPreflightError.wrongChain }
        let nonce = try await quantity(url, "eth_getTransactionCount", [sender, "pending"], max: 10_000_000_000)
        let balance = try WalletEVMUnits.decimalFromHex(try await rpc(url, "eth_getBalance", [sender, "pending"]))
        let block = try await rpcObject(url, "eth_getBlockByNumber", ["latest", false])
        guard let baseFeeHex = block["baseFeePerGas"] as? String else { throw WalletEVMPreflightError.estimate }
        let baseFee = try WalletEVMUnits.integer(baseFeeHex, upperBound: 1_000_000_000_000)
        let priority = try await quantity(url, "eth_maxPriorityFeePerGas", [], max: 1_000_000_000_000)
        guard baseFee <= 1_000_000_000_000, priority <= 1_000_000_000_000,
              baseFee <= (UInt64.max - priority) / 2 else { throw WalletEVMPreflightError.feeTooLarge }
        let maxFeePerGas = baseFee * 2 + priority
        guard maxFeePerGas > 0 else { throw WalletEVMPreflightError.estimate }

        var call: [String: Any] = ["from": sender]
        if let contract = asset.contract {
            call["to"] = contract
            call["value"] = "0x0"
            call["data"] = try WalletEVMUnits.transferData(to: recipient, baseUnits: units)
            let balanceData = "0x70a08231" + String(repeating: "0", count: 24) + String(sender.dropFirst(2)).lowercased()
            let tokenWei = try WalletEVMUnits.decimalFromHex(try await rpc(url, "eth_call", [["to": contract, "data": balanceData], "pending"]))
            guard tokenWei >= (try WalletEVMUnits.decimal(units)) else { throw WalletEVMPreflightError.insufficientTokens }
        } else {
            call["to"] = recipient
            call["value"] = try WalletEVMUnits.hexFromDecimal(units)
        }
        let estimate = try await quantity(url, "eth_estimateGas", [call], max: 10_000_000)
        guard estimate >= 21_000, estimate <= 10_000_000 else { throw WalletEVMPreflightError.estimate }
        // 20% gas headroom; cap to protect against unexpectedly large estimates.
        let gasLimit = estimate + (estimate / 5)
        let maxFeeWei = Decimal(Int(gasLimit)) * Decimal(Int(maxFeePerGas))
        guard maxFeeWei > 0 else { throw WalletEVMPreflightError.feeTooLarge }
        let ethAmount = asset == .eth ? try WalletEVMUnits.decimal(units) : Decimal.zero
        guard balance >= ethAmount + maxFeeWei else { throw WalletEVMPreflightError.insufficientETH }
        return WalletEVMQuote(asset: asset, sender: sender, recipient: recipient, amount: amount,
                              nonce: nonce, gasLimit: gasLimit, maxFeePerGas: maxFeePerGas,
                              priorityFeePerGas: priority, maxFeeETH: WalletEVMUnits.ethString(maxFeeWei),
                              provider: url.host ?? "RPC", checkedAt: Date())
    }

    private func quantity(_ url: URL, _ method: String, _ params: [Any], max: UInt64) async throws -> UInt64 {
        try WalletEVMUnits.integer(try await rpc(url, method, params), upperBound: max)
    }

    private func rpcObject(_ url: URL, _ method: String, _ params: [Any]) async throws -> [String: Any] {
        let result = try await request(url, method, params)
        guard let object = result as? [String: Any] else { throw WalletEVMPreflightError.estimate }
        return object
    }

    private func rpc(_ url: URL, _ method: String, _ params: [Any]) async throws -> String {
        let result = try await request(url, method, params)
        guard let hex = result as? String else { throw WalletEVMPreflightError.estimate }
        return hex
    }

    private func request(_ url: URL, _ method: String, _ params: [Any]) async throws -> Any {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 7, "method": method, "params": params])
        let (bytes, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), bytes.count <= 65_536,
              let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              json["jsonrpc"] as? String == "2.0", (json["id"] as? Int) == 7,
              json["error"] == nil, let result = json["result"], !(result is NSNull) else {
            throw WalletEVMPreflightError.rpc("Неверный ответ \(method)")
        }
        return result
    }
}
