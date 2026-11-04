import Foundation
import SwiftUI
import LocalAuthentication

@MainActor
final class WalletUSDTTransferStore: ObservableObject {
    @Published private(set) var records: [WalletUSDTTransferRecord] = []
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    private let journal: WalletUSDTTransferJournal
    private var context: LAContext?
    private var generation = UUID()
    private var refreshing = false
    private var publication: WalletUSDTPublication { WalletUSDTPublication(journal: journal) }
    private var announcing = false

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("unavailable")
        journal = WalletUSDTTransferJournal(file: folder.appendingPathComponent("SpyderTransfers/usdt-v1.json"))
    }
    func reload() async {
        do { records = try await journal.all() }
        catch { self.error = error.localizedDescription }
    }
    func cancelAuthorization() { generation = UUID(); context?.invalidate(); context = nil }

    func send(intent: WalletEVMUnsignedIntent, quote: WalletEVMQuote, walletID: String,
              recipient: SpyderChatRecipient, server: String, authorize: @escaping () -> Bool) async -> WalletUSDTTransferRecord? {
        guard !busy else { return nil }
        busy = true; error = nil
        let action = UUID(); generation = action
        defer { busy = false; context = nil }
        do {
            guard authorize(), intent.asset == .usdt, recipient.payment.asset == .usdtEthereum,
                  recipient.payment.address?.caseInsensitiveCompare(intent.recipient) == .orderedSame,
                  WalletEthereumSignature.verifyOwnership(recipient.payment, requester: recipient.ownerID,
                    receiver: recipient.peerID, server: server),
                  let endpoint = WalletEthereumRPC.endpoints.first(where: { $0.host == quote.provider }) else {
                throw WalletUSDTTransferError.unprovenAddress
            }
            try intent.ensureFresh()
            let existing = try await journal.all()
            guard !existing.contains(where: { !$0.final && $0.intent.sender.caseInsensitiveCompare(intent.sender) == .orderedSame }) else {
                throw WalletUSDTTransferError.duplicate
            }
            // Revalidate balances and the nonce immediately before requesting user presence.
            let latest = try await WalletEVMPreflightClient(endpoints: [endpoint]).quote(sender: intent.sender,
                recipient: intent.recipient, amount: intent.amount, asset: .usdt)
            guard latest.nonce == intent.nonce, latest.gasLimit <= intent.gasLimit,
                  latest.maxFeePerGas <= intent.maxFeePerGas, latest.priorityFeePerGas <= intent.priorityFeePerGas,
                  generation == action, authorize() else { throw WalletUSDTTransferError.stale }
            let binding = WalletUSDTChatBinding(requestID: recipient.payment.requestID, ownerID: recipient.ownerID,
                peerID: recipient.peerID, server: server, addressIssuedAt: recipient.payment.issuedAt)
            let auth = LAContext(); context = auth
            // No biometric reuse window; this vault read requests user presence for this exact review.
            auth.touchIDAuthenticationAllowableReuseDuration = 0
            let signature = try await Task.detached(priority: .userInitiated) {
                try WalletEVMOfflineSigner.sign(intent: intent, walletID: walletID, context: auth, binding: binding)
            }.value
            // Face ID can briefly keep the scene inactive after returning the result.
            for _ in 0..<20 {
                if authorize() { break }
                guard generation == action else { throw WalletUSDTTransferError.cancelled }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard generation == action, authorize(), recipient.payment.isValid() else { throw WalletUSDTTransferError.cancelled }
            try intent.ensureFresh()
            let rpc = WalletEthereumRPC()
            guard try await rpc.chainAndNonce(endpoint: endpoint, sender: intent.sender) == intent.nonce,
                  generation == action, authorize() else { throw WalletUSDTTransferError.stale }
            let verified = try WalletEthereumSignature.verifiedTransfer(raw: signature.encoded, intent: intent,
                binding: binding, authorizationSignature: signature.authorizationSignature)
            try intent.ensureFresh()
            let record = WalletUSDTTransferRecord(id: UUID(), walletID: walletID, ownerID: recipient.ownerID,
                peerID: recipient.peerID, requestID: recipient.payment.requestID, server: server,
                intent: intent, txHash: verified.hash, submittedAt: Int(Date().timeIntervalSince1970),
                binding: binding, authorizationSignature: signature.authorizationSignature, stage: .reserved)
            guard SpyderTransferEnvelope(requestID: record.requestID, txHash: record.txHash,
                intent: intent, submittedAt: record.submittedAt, binding: record.binding, authorizationSignature: record.authorizationSignature).payload != nil else { throw WalletUSDTTransferError.invalid }
            // Preserve the known hash in memory even if a post-publication disk update fails.
            records.append(record)
            _ = try await publication.publish(record: record, payload: verified, endpoint: endpoint,
                authorize: { self.generation == action && authorize() })
            await reload()
            return records.first(where: { $0.id == record.id })
        } catch {
            self.error = error.localizedDescription
            await reload() // Also discovers a reservation if an ambiguous post-send persistence failed.
            return nil
        }
    }
    func refresh(walletID: String) async {
        guard !refreshing, !busy else { return }
        refreshing = true; defer { refreshing = false }
        do { try await journal.reopenAfterUnlock() }
        catch { self.error = error.localizedDescription; return }
        await reload()
        for record in records.filter({ $0.walletID == walletID && !$0.final }).suffix(20) {
            do {
                let result = try await WalletEVMOutgoingTracker().reconcile(txHash: record.txHash, intent: record.intent, notBefore: record.binding?.addressIssuedAt)
                switch result {
                case .confirmed: try await journal.update(record.id, stage: .confirmed)
                case .reverted: try await journal.update(record.id, stage: .reverted)
                default: break // notSeen/timeout is never permission to repeat a financial transfer.
                }
            } catch { /* Preserve the uncertain attempt, including when a provider is unavailable. */ }
        }
        await reload()
    }
    func announce(chat: SpyderChatStore) async {
        guard !announcing else { return }
        announcing = true; defer { announcing = false }
        await reload()
        for record in records where record.stage != .reserved && !record.announced && record.ownerID == chat.activePersonaID && record.server == chat.serverAddress {
            guard let payload = SpyderTransferEnvelope(requestID: record.requestID, txHash: record.txHash,
                intent: record.intent, submittedAt: record.submittedAt, binding: record.binding, authorizationSignature: record.authorizationSignature).payload else { continue }
            // Stable persisted client ID prevents a duplicate chat card after timeout/restart.
            if await chat.sendMessage(to: record.peerID, text: payload, clientID: record.id.uuidString.lowercased()) {
                do { try await journal.update(record.id, announced: true) } catch { self.error = error.localizedDescription }
            }
        }
        await reload()
    }
}
