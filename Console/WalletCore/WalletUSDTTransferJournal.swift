import Foundation

enum WalletUSDTTransferError: LocalizedError {
    case unavailable, duplicate, invalid, stale, cancelled, unprovenAddress
    var errorDescription: String? {
        switch self {
        case .unavailable: "Журнал переводов недоступен. Отправка остановлена."
        case .duplicate: "Есть незавершённая попытка с этого адреса. Сначала проверь её статус."
        case .invalid: "Параметры перевода не прошли проверку."
        case .stale: "Комиссия или nonce изменились. Обнови расчёт и подтверди перевод заново."
        case .cancelled: "Подтверждение перевода отменено."
        case .unprovenAddress: "Запроси реквизиты с подтверждением владения адресом в обновлённом приложении."
        }
    }
}

struct WalletUSDTTransferRecord: Codable, Equatable, Identifiable, Sendable {
    enum Stage: String, Codable, Sendable { case reserved, resultUnknown, acknowledged, confirmed, reverted }
    let id: UUID
    let walletID: String
    let ownerID: String
    let peerID: String
    let requestID: UUID
    let server: String
    let intent: WalletEVMUnsignedIntent
    let txHash: String
    let submittedAt: Int
    var binding: WalletUSDTChatBinding? = nil
    var authorizationSignature: String? = nil
    var stage: Stage
    var announced = false
    var final: Bool { stage == .confirmed || stage == .reverted }

    var valid: Bool {
        guard !walletID.isEmpty, walletID.count <= 128, intent.asset == .usdt,
              ownerID.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil,
              peerID.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil,
              server.hasPrefix("https://"), URL(string: server)?.host != nil,
              txHash.range(of: "^0x[0-9a-f]{64}$", options: .regularExpression) != nil,
              submittedAt > 0, submittedAt <= Int(Date().timeIntervalSince1970) + 300 else { return false }
        let quote = WalletEVMQuote(asset: intent.asset, sender: intent.sender, recipient: intent.recipient,
            amount: intent.amount, nonce: intent.nonce, gasLimit: intent.gasLimit, maxFeePerGas: intent.maxFeePerGas,
            priorityFeePerGas: intent.priorityFeePerGas, maxFeeETH: "", provider: "journal", checkedAt: intent.checkedAt)
        guard let rebuilt = try? WalletEVMUnsignedIntent(quote: quote, expectedSender: intent.sender, now: intent.checkedAt),
              rebuilt == intent else { return false }
        if binding != nil || authorizationSignature != nil {
            guard let binding, binding.valid, binding.requestID == requestID, binding.ownerID == ownerID,
                  binding.peerID == peerID, binding.server == server, binding.addressIssuedAt <= submittedAt + 300,
                  authorizationSignature?.range(of: "^0x[0-9a-f]{130}$", options: .regularExpression) != nil else { return false }
        }
        return true
    }
}

/// One process owns this actor. Only public intent/hash metadata is persisted; no signed bytes or secrets.
actor WalletUSDTTransferJournal {
    private let file: URL
    private var poisoned = false
    private var loaded = false
    private var hadJournal = false
    private var records: [WalletUSDTTransferRecord] = []
    init(file: URL) { self.file = file }
    private func load() throws {
        guard !poisoned else { throw WalletUSDTTransferError.unavailable }
        if loaded { return }
        do {
            let data: Data
            do { data = try Data(contentsOf: file) }
            catch let failure as CocoaError where failure.code == .fileReadNoSuchFile {
                guard !hadJournal else { throw WalletUSDTTransferError.unavailable }
                records = []; loaded = true; return
            }
            let decoded = try JSONDecoder().decode([WalletUSDTTransferRecord].self, from: data)
            guard decoded.count <= 10000, decoded.allSatisfy(\.valid),
                  Set(decoded.map(\.id)).count == decoded.count,
                  Set(decoded.map(\.txHash)).count == decoded.count,
                  Set(decoded.map { "\($0.intent.sender.lowercased()):\($0.intent.nonce)" }).count == decoded.count else {
                throw WalletUSDTTransferError.invalid
            }
            records = decoded; hadJournal = true; loaded = true
        } catch { poisoned = true; throw WalletUSDTTransferError.unavailable }
    }
    private func commit(_ next: [WalletUSDTTransferRecord]) throws {
        do {
            let directory = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var folder = directory; try folder.setResourceValues(values)
            let data = try JSONEncoder().encode(next)
            #if os(iOS)
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: file, options: .atomic)
            #endif
            hadJournal = true
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.synchronize()
            records = next
        } catch {
            // A write may have reached disk before an error. Never keep accepting reservations in memory.
            poisoned = true; throw WalletUSDTTransferError.unavailable
        }
    }
    func reopenAfterUnlock() throws {
        guard poisoned else { return }
        // A transient protection/write failure may clear after unlock. Re-read and validate the
        // durable state; never replace a missing/corrupt journal with an empty in-memory history.
        guard FileManager.default.fileExists(atPath: file.path) || (!hadJournal && records.isEmpty) else {
            throw WalletUSDTTransferError.unavailable
        }
        poisoned = false; loaded = false
        try load()
    }
    func cancelBeforePublication(_ id: UUID) throws {
        try load()
        guard let record = records.first(where: { $0.id == id }), record.stage == .reserved else { throw WalletUSDTTransferError.invalid }
        try commit(records.filter { $0.id != id })
    }
    func all() throws -> [WalletUSDTTransferRecord] { try load(); return records }
    func reserve(_ value: WalletUSDTTransferRecord) throws {
        try load()
        guard value.valid, value.stage == .reserved, records.count < 10000 else { throw WalletUSDTTransferError.invalid }
        guard !records.contains(where: { existing in
            existing.txHash == value.txHash || existing.id == value.id ||
            (existing.intent.sender.caseInsensitiveCompare(value.intent.sender) == .orderedSame &&
             (!existing.final || existing.intent.nonce == value.intent.nonce))
        }) else { throw WalletUSDTTransferError.duplicate }
        try commit(records + [value]) // Commit BEFORE the first eth_sendRawTransaction call.
    }
    func update(_ id: UUID, stage: WalletUSDTTransferRecord.Stage? = nil, announced: Bool? = nil) throws {
        try load()
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw WalletUSDTTransferError.invalid }
        var next = records
        if let stage { next[index].stage = stage }
        if let announced { next[index].announced = announced }
        try commit(next)
    }
}
