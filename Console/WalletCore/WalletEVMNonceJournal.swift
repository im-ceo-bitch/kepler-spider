import Foundation

// Stage 6 test-only durable nonce reservation. Not a release broadcaster.
// Store only public metadata: NEVER raw signed bytes or mnemonic/private keys.
// This is single-process coordination, not yet a multi-process transaction manager.
#if SPYDER_EVM_RELAY_TESTS
enum WalletEVMJournalError: Error, Equatable {
    case invalidRecord, busyNonce, duplicateTransaction, storageUnavailable, invalidTransition
}

struct WalletEVMJournalEntry: Codable, Equatable {
    enum Status: String, Codable { case reserved, resultUnknown, acknowledged }
    let walletID: String
    let sender: String
    let chainID: UInt64
    let nonce: UInt64
    let txHash: String
    var status: Status
}

actor WalletEVMNonceJournal {
    private let file: URL
    private var entries: [WalletEVMJournalEntry]

    init(file: URL) throws {
        guard file.isFileURL else { throw WalletEVMJournalError.storageUnavailable }
        self.file = file
        let loaded: [WalletEVMJournalEntry]
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let data = try Data(contentsOf: file)
                let decoded = try JSONDecoder().decode([WalletEVMJournalEntry].self, from: data)
                guard decoded.count <= 10_000 && decoded.allSatisfy(Self.valid) else {
                    throw WalletEVMJournalError.invalidRecord
                }
                let unique = Set(decoded.map { "\($0.chainID):\($0.sender.lowercased()):\($0.nonce)" })
                guard unique.count == decoded.count else { throw WalletEVMJournalError.invalidRecord }
                loaded = decoded
            } catch { throw WalletEVMJournalError.invalidRecord }
        } else { loaded = [] }
        entries = loaded
    }

    private static func valid(_ e: WalletEVMJournalEntry) -> Bool {
        !e.walletID.isEmpty && e.walletID.count <= 128 && e.chainID == 1 && e.nonce <= 10_000_000_000 &&
        e.sender.range(of: "^0x[0-9a-fA-F]{40}$", options: .regularExpression) != nil &&
        e.txHash.range(of: "^0x[0-9a-fA-F]{64}$", options: .regularExpression) != nil
    }

    private func persist(_ next: [WalletEVMJournalEntry]) throws {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(next)
            // Atomic replacement; no automatic retry after an uncertain network response.
            #if os(iOS)
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: file, options: .atomic)
            #endif
            var attributes = URLResourceValues()
            attributes.isExcludedFromBackup = true
            var target = file
            try target.setResourceValues(attributes)
        } catch { throw WalletEVMJournalError.storageUnavailable }
    }

    // Must commit before any network attempt. Do not remove entries automatically.
    func reserve(_ entry: WalletEVMJournalEntry) throws {
        guard Self.valid(entry), entry.status == .reserved else { throw WalletEVMJournalError.invalidRecord }
        if entries.contains(where: { $0.txHash.caseInsensitiveCompare(entry.txHash) == .orderedSame }) {
            throw WalletEVMJournalError.duplicateTransaction
        }
        if entries.contains(where: {
            $0.chainID == entry.chainID && $0.sender.caseInsensitiveCompare(entry.sender) == .orderedSame && $0.nonce == entry.nonce
        }) { throw WalletEVMJournalError.busyNonce }
        let next = entries + [entry]
        try persist(next)
        entries = next
    }

    func mark(_ hash: String, status: WalletEVMJournalEntry.Status) throws {
        guard status != .reserved, let i = entries.firstIndex(where: { $0.txHash.caseInsensitiveCompare(hash) == .orderedSame }) else {
            throw WalletEVMJournalError.invalidTransition
        }
        // After uncertain result, even an RPC acknowledgement cannot initiate another send.
        if entries[i].status == .acknowledged && status == .resultUnknown { throw WalletEVMJournalError.invalidTransition }
        var next = entries
        next[i].status = status
        try persist(next)
        entries = next
    }

    func all() -> [WalletEVMJournalEntry] { entries }
}
#endif
