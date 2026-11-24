import Foundation

// Test double for the cryptographic boundary. Actual Wallet Core recovery runs in XCTest.
struct WalletUSDTVerifiedPayload: Sendable {
    let raw: Data
    let intent: WalletEVMUnsignedIntent
    let hash: String
    var binding: WalletUSDTChatBinding? = nil
    var authorizationSignature: String? = nil
}
actor SpyderMockRPC {
    var attempts = 0
    let journal: WalletUSDTTransferJournal
    let acknowledged: Bool
    let hash: String
    init(journal: WalletUSDTTransferJournal, acknowledged: Bool, hash: String) {
        self.journal = journal; self.acknowledged = acknowledged; self.hash = hash
    }
    func call(_ url: URL, _ method: String, _ params: [String]) async throws -> String? {
        precondition(method == "eth_sendRawTransaction")
        let saved = try await journal.all()
        precondition(saved.count == 1 && saved[0].stage == .resultUnknown, "network preceded durable publication marker")
        attempts += 1
        if acknowledged { return hash }
        throw URLError(.timedOut)
    }
}

@main struct USDTReleaseTests {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = Date(), raw = Data([2]) + Data(repeating: 0x42, count: 100)
        let quote = WalletEVMQuote(asset: .usdt, sender: "0x1111111111111111111111111111111111111111",
            recipient: "0x2222222222222222222222222222222222222222", amount: "1.000001", nonce: 3,
            gasLimit: 70000, maxFeePerGas: 3000000000, priorityFeePerGas: 1000000000,
            maxFeeETH: "0.00021", provider: "fixture", checkedAt: now)
        let intent = try WalletEVMUnsignedIntent(quote: quote, expectedSender: quote.sender)
        let binding = WalletUSDTChatBinding(requestID: UUID(), ownerID: String(repeating: "a", count: 32),
            peerID: String(repeating: "b", count: 32), server: "https://example.com", addressIssuedAt: Int(now.timeIntervalSince1970) - 1)
        let announcementSignature = "0x" + String(repeating: "1", count: 130)
        func record(_ hash: String) -> WalletUSDTTransferRecord {
            WalletUSDTTransferRecord(id: UUID(), walletID: "test-wallet", ownerID: String(repeating: "a", count: 32),
                peerID: String(repeating: "b", count: 32), requestID: binding.requestID, server: "https://example.com",
                intent: intent, txHash: hash, submittedAt: Int(now.timeIntervalSince1970), binding: binding, authorizationSignature: announcementSignature, stage: .reserved)
        }
        let file = folder.appendingPathComponent("unknown/journal.json")
        let journal = WalletUSDTTransferJournal(file: file)
        let hash = WalletEVMKeccak256.hex(raw)
        let payload = WalletUSDTVerifiedPayload(raw: raw, intent: intent, hash: hash, binding: binding, authorizationSignature: announcementSignature)
        let mock = SpyderMockRPC(journal: journal, acknowledged: false, hash: hash)
        let rpc = WalletEthereumRPC(transport: { url, method, params in try await mock.call(url, method, params) })
        let publisher = WalletUSDTPublication(journal: journal, rpc: rpc)
        let value = record(hash)
        let state = try await publisher.publish(record: value, payload: payload, endpoint: WalletEthereumRPC.endpoints[0], authorize: { true })
        precondition(state == .resultUnknown)
        let saved = try await journal.all(); precondition(saved[0].stage == .resultUnknown)
        let data = try String(contentsOf: file, encoding: .utf8)
        precondition(!data.contains("privateKey") && !data.contains("encoded") && !data.contains("mnemonic"))
        do {
            _ = try await publisher.publish(record: value, payload: payload, endpoint: WalletEthereumRPC.endpoints[0], authorize: { true })
            fatalError("duplicate was sent")
        } catch WalletUSDTTransferError.duplicate { }
        let restarted = WalletUSDTTransferJournal(file: file)
        do { try await restarted.reserve(record(hash)); fatalError("restart lost nonce claim") }
        catch WalletUSDTTransferError.duplicate { }
        let attempts = await mock.attempts; precondition(attempts == 1)

        let cancelFile = folder.appendingPathComponent("cancel/journal.json")
        let cancelJournal = WalletUSDTTransferJournal(file: cancelFile)
        let cancelMock = SpyderMockRPC(journal: cancelJournal, acknowledged: true, hash: hash)
        let cancelPublisher = WalletUSDTPublication(journal: cancelJournal,
            rpc: WalletEthereumRPC(transport: { u, m, p in try await cancelMock.call(u, m, p) }))
        var checks = 0
        do {
            _ = try await cancelPublisher.publish(record: record(hash), payload: payload, endpoint: WalletEthereumRPC.endpoints[0],
                authorize: { checks += 1; return checks == 1 })
            fatalError("cancellation after reserve did not stop publication")
        } catch WalletUSDTTransferError.cancelled { }
        let cancelled = try await cancelJournal.all(); precondition(cancelled.isEmpty)
        let cancelAttempts = await cancelMock.attempts; precondition(cancelAttempts == 0)
        _ = try await cancelPublisher.publish(record: record(hash), payload: payload, endpoint: WalletEthereumRPC.endpoints[0], authorize: { true })
        let acknowledged = try await cancelJournal.all(); precondition(acknowledged[0].stage == .acknowledged)

        let confirmedID = acknowledged[0].id
        try await cancelJournal.update(confirmedID, stage: .confirmed, announced: true, finalized: true)
        for stage: WalletUSDTTransferRecord.Stage in [.reserved, .resultUnknown, .acknowledged, .reverted] {
            do { try await cancelJournal.update(confirmedID, stage: stage); fatalError("terminal state downgraded") }
            catch WalletUSDTTransferError.invalid { }
        }
        do { try await cancelJournal.update(confirmedID, announced: false); fatalError("announcement reset") }
        catch WalletUSDTTransferError.invalid { }
        let terminal = try await cancelJournal.all()
        precondition(terminal[0].stage == .confirmed && terminal[0].announced)
        // A second wallet and nonce must not settle a previously confirmed request.
        let secondQuote = WalletEVMQuote(asset: .usdt, sender: "0x3333333333333333333333333333333333333333",
            recipient: quote.recipient, amount: quote.amount, nonce: 8, gasLimit: quote.gasLimit,
            maxFeePerGas: quote.maxFeePerGas, priorityFeePerGas: quote.priorityFeePerGas,
            maxFeeETH: quote.maxFeeETH, provider: quote.provider, checkedAt: now)
        let secondIntent = try WalletEVMUnsignedIntent(quote: secondQuote, expectedSender: secondQuote.sender, now: now)
        let secondRecord = WalletUSDTTransferRecord(id: UUID(), walletID: "second-wallet", ownerID: value.ownerID,
            peerID: value.peerID, requestID: value.requestID, server: value.server, intent: secondIntent,
            txHash: "0x" + String(repeating: "c", count: 64), submittedAt: value.submittedAt,
            binding: binding, authorizationSignature: announcementSignature, stage: .reserved)
        do { try await cancelJournal.reserve(secondRecord); fatalError("confirmed request paid twice") }
        catch WalletUSDTTransferError.requestAlreadyPaid { }
        do { try await journal.reserve(secondRecord); fatalError("uncertain request paid twice") }
        catch WalletUSDTTransferError.requestAlreadyPaid { }
        let retryJournal = WalletUSDTTransferJournal(file: folder.appendingPathComponent("retry/journal.json"))
        try await retryJournal.reserve(value)
        try await retryJournal.update(value.id, stage: .reverted, finalized: true)
        try await retryJournal.reserve(secondRecord)
        let retryRecords = try await retryJournal.all(); precondition(retryRecords.count == 2)
        let staleJournal = WalletUSDTTransferJournal(file: folder.appendingPathComponent("stale/journal.json"))
        let staleTime = now.addingTimeInterval(-60)
        let staleQuote = WalletEVMQuote(asset: quote.asset, sender: quote.sender, recipient: quote.recipient,
            amount: quote.amount, nonce: quote.nonce, gasLimit: quote.gasLimit, maxFeePerGas: quote.maxFeePerGas,
            priorityFeePerGas: quote.priorityFeePerGas, maxFeeETH: quote.maxFeeETH, provider: quote.provider, checkedAt: staleTime)
        let staleIntent = try WalletEVMUnsignedIntent(quote: staleQuote, expectedSender: quote.sender, now: staleTime)
        let staleRecord = WalletUSDTTransferRecord(id: UUID(), walletID: value.walletID, ownerID: value.ownerID,
            peerID: value.peerID, requestID: value.requestID, server: value.server, intent: staleIntent,
            txHash: hash, submittedAt: value.submittedAt, binding: binding, authorizationSignature: announcementSignature, stage: .reserved)
        let stalePayload = WalletUSDTVerifiedPayload(raw: raw, intent: staleIntent, hash: hash, binding: binding, authorizationSignature: announcementSignature)
        do { _ = try await WalletUSDTPublication(journal: staleJournal, rpc: rpc).publish(record: staleRecord,
            payload: stalePayload, endpoint: WalletEthereumRPC.endpoints[0], authorize: { true }); fatalError("expired signature published") }
        catch WalletEVMSigningError.outdatedQuote { }
        let staleRecords = try await staleJournal.all(); precondition(staleRecords.isEmpty)
        let corruptFile = folder.appendingPathComponent("bad.json")
        try Data("not JSON".utf8).write(to: corruptFile)
        let corrupt = WalletUSDTTransferJournal(file: corruptFile)
        do { try await corrupt.reserve(record(hash)); fatalError("corruption bypassed journal") }
        catch WalletUSDTTransferError.unavailable { }
        do { try await corrupt.reopenAfterUnlock(); fatalError("corruption reset to empty") }
        catch WalletUSDTTransferError.unavailable { }
        let recoveryFile = folder.appendingPathComponent("recover.json")
        try FileManager.default.createDirectory(at: recoveryFile, withIntermediateDirectories: true)
        let recovery = WalletUSDTTransferJournal(file: recoveryFile)
        do { _ = try await recovery.all(); fatalError("unreadable journal accepted") }
        catch WalletUSDTTransferError.unavailable { }
        try FileManager.default.removeItem(at: recoveryFile)
        try JSONEncoder().encode([value]).write(to: recoveryFile)
        try await recovery.reopenAfterUnlock()
        let restored = try await recovery.all(); precondition(restored.count == 1 && restored[0].txHash == hash)
        do { try await recovery.reserve(value); fatalError("unlock discarded nonce reservation") }
        catch WalletUSDTTransferError.duplicate { }
        let mismatch = WalletUSDTPublication(journal: WalletUSDTTransferJournal(file: folder.appendingPathComponent("mismatch.json")))
        do {
            _ = try await mismatch.publish(record: record("0x" + String(repeating: "a", count: 64)), payload: payload,
                endpoint: WalletEthereumRPC.endpoints[0], authorize: { true })
            fatalError("hash mismatch accepted")
        } catch WalletUSDTTransferError.invalid { }
        let overflow = WalletUSDTTransferRecord(id: UUID(), walletID: "fixture", ownerID: binding.ownerID,
            peerID: binding.peerID, requestID: binding.requestID, server: binding.server, intent: intent,
            txHash: hash, submittedAt: Int.max, binding: binding, authorizationSignature: announcementSignature, stage: .reserved)
        precondition(!overflow.valid, "malformed timestamp must be rejected without overflow")
        let unbound = WalletUSDTVerifiedPayload(raw: raw, intent: intent, hash: hash)
        do {
            _ = try await mismatch.publish(record: record(hash), payload: unbound,
                endpoint: WalletEthereumRPC.endpoints[0], authorize: { true })
            fatalError("unsigned chat context reached publication")
        } catch WalletUSDTTransferError.invalid { }
        // Existing journal written before finalized evidence: preserve it, but do not permit a retry.
        let oldFile = folder.appendingPathComponent("legacy-revert.json")
        var oldRevert = value; oldRevert.stage = .reverted
        try JSONEncoder().encode([oldRevert]).write(to: oldFile)
        let old = WalletUSDTTransferJournal(file: oldFile)
        let oldRecords = try await old.all(); precondition(oldRecords[0].final == false && !oldRecords[0].permitsRetry)
        do { try await old.reserve(secondRecord); fatalError("legacy revert allowed a duplicate") }
        catch WalletUSDTTransferError.requestAlreadyPaid { }
        do { try await old.update(value.id, stage: .reverted); fatalError("unfinalized revert accepted") }
        catch WalletUSDTTransferError.invalid { }
        try await old.update(value.id, stage: .confirmed, finalized: true)
        let corrected = try await old.all(); precondition(corrected[0].stage == .confirmed && corrected[0].finalityVerified == true)
        let preparedFile = folder.appendingPathComponent("prepared/journal.json")
        let preparedJournal = WalletUSDTTransferJournal(file: preparedFile)
        try await preparedJournal.preparePublication(value)
        let prepared = try await preparedJournal.all(); precondition(prepared.first?.stage == .prepared)
        let reopened = WalletUSDTTransferJournal(file: preparedFile)
        try await reopened.recoverInterruptedPreparation()
        let recovered = try await reopened.all(); precondition(recovered.isEmpty)
        try await reopened.reserve(value)
        try await reopened.recoverInterruptedPreparation()
        let legacy = try await reopened.all(); precondition(legacy.first?.stage == .reserved)
        do { try await reopened.cancelBeforePublication(value.id); fatalError("legacy reservation discarded") }
        catch WalletUSDTTransferError.invalid { }
        try await journal.recoverInterruptedPreparation()
        let ambiguous = try await journal.all(); precondition(ambiguous.first?.stage == .resultUnknown && ambiguous.first?.canAnnounce == false)
        do { try await journal.update(value.id, announced: true); fatalError("unknown result announced") }
        catch WalletUSDTTransferError.invalid { }
        let late = WalletUSDTTransferJournal(file: folder.appendingPathComponent("late/journal.json"))
        let lateMock = SpyderMockRPC(journal: late, acknowledged: true, hash: hash)
        let latePublisher = WalletUSDTPublication(journal: late, rpc: WalletEthereumRPC(transport: { u, m, p in try await lateMock.call(u,m,p) }))
        var lateChecks = 0
        do { _ = try await latePublisher.publish(record: value, payload: payload, endpoint: WalletEthereumRPC.endpoints[0], authorize: { lateChecks += 1; return lateChecks < 3 }); fatalError("late cancellation sent") }
        catch WalletUSDTTransferError.cancelled { }
        let lateAttempts = await lateMock.attempts; precondition(lateAttempts == 0)
        let lateRecords = try await late.all(); precondition(lateRecords.first?.stage == .resultUnknown)
        print("USDT production publication tests passed: reservation order, timeout, duplicate, restart, cancellation, corruption, hash binding")
    }
}
