import Foundation

// Block 7 stage 2: local EIP-1559 signing foundation. No RPC broadcasting.
// Intentionally NOT invoked from WalletSendFlowView. A full Xcode build,
// signer-vector tests, secure-memory review and transaction audit are release gates.
enum WalletEVMSigningError: LocalizedError {
    case outdatedQuote, wrongWallet, invalidIntent, malformedHex, signingFailed

    var errorDescription: String? {
        switch self {
        case .outdatedQuote: "Проверка комиссии устарела. Повторите проверку сети."
        case .wrongWallet: "Адрес в подписи не совпадает с выбранным кошельком."
        case .invalidIntent: "Некорректные параметры Ethereum-транзакции."
        case .malformedHex: "Некорректные данные Ethereum-транзакции."
        case .signingFailed: "Wallet Core не смог создать корректную подпись EIP-1559."
        }
    }
}

/// Immutable, wallet-bound unsigned intent built only from a fresh, verified RPC quote.
/// None of these properties are secret. No custom contract call or token address is accepted.
struct WalletEVMUnsignedIntent: Equatable, Codable, Sendable {
    let asset: WalletEVMAsset
    let sender: String
    let recipient: String
    let amount: String
    let baseUnits: String
    let nonce: UInt64
    let gasLimit: UInt64
    let maxFeePerGas: UInt64
    let priorityFeePerGas: UInt64
    let checkedAt: Date

    init(quote: WalletEVMQuote, expectedSender: String, now: Date = Date()) throws {
        let age = now.timeIntervalSince(quote.checkedAt)
        guard age >= 0, age < 45 else { throw WalletEVMSigningError.outdatedQuote }
        guard WalletEVMUnits.isAddress(expectedSender),
              WalletEVMUnits.isAddress(quote.sender),
              quote.sender.caseInsensitiveCompare(expectedSender) == .orderedSame else {
            throw WalletEVMSigningError.wrongWallet
        }
        guard WalletEVMUnits.isAddress(quote.recipient),
              quote.recipient.caseInsensitiveCompare(quote.sender) != .orderedSame,
              quote.nonce <= 10_000_000_000,
              (21_000...10_000_000).contains(quote.gasLimit),
              quote.maxFeePerGas > 0, quote.maxFeePerGas <= 3_000_000_000_000,
              quote.priorityFeePerGas > 0, quote.priorityFeePerGas <= quote.maxFeePerGas else {
            throw WalletEVMSigningError.invalidIntent
        }
        let units = try WalletEVMUnits.baseUnits(quote.amount, decimals: quote.asset.decimals)
        guard !units.isEmpty else { throw WalletEVMSigningError.invalidIntent }
        self.asset = quote.asset
        self.sender = quote.sender
        self.recipient = quote.recipient
        self.amount = quote.amount
        self.baseUnits = units
        self.nonce = quote.nonce
        self.gasLimit = quote.gasLimit
        self.maxFeePerGas = quote.maxFeePerGas
        self.priorityFeePerGas = quote.priorityFeePerGas
        self.checkedAt = quote.checkedAt
    }

    var transactionTarget: String { asset.contract ?? recipient }

    var tokenCallData: String? {
        guard asset != .eth else { return nil }
        return try? WalletEVMUnits.transferData(to: recipient, baseUnits: baseUnits)
    }

    func ensureFresh(now: Date = Date()) throws {
        let age = now.timeIntervalSince(checkedAt)
        guard age >= 0 && age < 45 else { throw WalletEVMSigningError.outdatedQuote }
    }
}

/// Decimal-safe and endian-safe encoding; no Float/Double conversion.
enum WalletEVMSigningBytes {
    static func quantity(_ value: UInt64) -> Data {
        guard value != 0 else { return Data() }
        var result = [UInt8]()
        var remaining = value
        while remaining != 0 {
            result.append(UInt8(remaining & 0xff))
            remaining >>= 8
        }
        return Data(result.reversed())
    }

    static func hex(_ input: String, maxBytes: Int = 32) throws -> Data {
        guard input.hasPrefix("0x") else { throw WalletEVMSigningError.malformedHex }
        var digits = String(input.dropFirst(2))
        guard (1...512).contains(maxBytes), digits.count <= maxBytes * 2, digits.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 70) || ($0 >= 97 && $0 <= 102) }) else {
            throw WalletEVMSigningError.malformedHex
        }
        if digits.count % 2 != 0 { digits.insert("0", at: digits.startIndex) }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(digits.count / 2)
        let values = Array(digits.utf8)
        for index in stride(from: 0, to: values.count, by: 2) {
            func nibble(_ c: UInt8) -> UInt8 {
                if c >= 97 { return c - 87 }
                if c >= 65 { return c - 55 }
                return c - 48
            }
            bytes.append((nibble(values[index]) << 4) | nibble(values[index + 1]))
        }
        return Data(bytes)
    }

    static func decimal(_ units: String) throws -> Data {
        try hex(WalletEVMUnits.hexFromDecimal(units))
    }
}

