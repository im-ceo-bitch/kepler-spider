import Foundation

/// Shared production/test boundary: durable nonce claim, authorization recheck, one network attempt.
actor WalletUSDTPublication {
    private let journal: WalletUSDTTransferJournal
    private let rpc: WalletEthereumRPC
    private var busy = false
    init(journal: WalletUSDTTransferJournal, rpc: WalletEthereumRPC = WalletEthereumRPC()) {
        self.journal = journal; self.rpc = rpc
    }
    func publish(record: WalletUSDTTransferRecord, payload: WalletUSDTVerifiedPayload, endpoint: URL,
                 authorize: @escaping @MainActor () -> Bool) async throws -> WalletUSDTTransferRecord.Stage {
        guard !busy else { throw WalletUSDTTransferError.duplicate }
        busy = true; defer { busy = false }
        guard record.valid, let binding = record.binding, binding.valid,
              record.authorizationSignature != nil, payload.binding == binding,
              payload.authorizationSignature == record.authorizationSignature, payload.intent == record.intent, payload.hash == record.txHash,
              payload.raw.first == 2, payload.raw.count <= 2048,
              WalletEVMKeccak256.hex(payload.raw) == record.txHash,
              WalletEthereumRPC.endpoints.contains(endpoint), await authorize() else { throw WalletUSDTTransferError.invalid }
        try await journal.reserve(record)
        guard await authorize() else {
            try await journal.cancelBeforePublication(record.id)
            throw WalletUSDTTransferError.cancelled
        }
        // One attempt after the explicit authorization boundary; no retry or provider failover.
        let acknowledged = await rpc.publish(raw: payload.raw, hash: record.txHash, endpoint: endpoint)
        let state: WalletUSDTTransferRecord.Stage = acknowledged ? .acknowledged : .resultUnknown
        try await journal.update(record.id, stage: state)
        return state
    }
}
