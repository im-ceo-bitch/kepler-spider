import SwiftUI

struct SpyderTransferStatusView: View {
    let transfer: SpyderTransferEnvelope
    var enabled = true
    var outgoing = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.spyderChatSectionActive) private var sectionActive
    @State private var assessment: WalletEVMOutgoingAssessment?
    @State private var error: String?
    @State private var checkedAt: Date?

    private var status: String {
        if error != nil { return "Проверка сети недоступна" }
        switch assessment {
        case .confirmed: return outgoing ? "Перевод подтверждён в Ethereum" : "Получено в Ethereum"
        case .reverted: return "Транзакция завершилась ошибкой"
        case .observed(let proof, let providers): return "В блоке · \(proof.confirmations) подтверждений · \(providers)/2 источников"
        case .pending: return "Ожидает включения в блок"
        case .notSeen: return "Результат отправки пока неизвестен"
        case nil: return "Проверяем транзакцию…"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(transfer.intent.amount + " USDT", systemImage: outgoing ? "arrow.up.right" : "arrow.down.left")
                .font(.headline)
            Text("Ethereum · ERC-20").font(.caption).foregroundStyle(.secondary)
            Text(status).font(.subheadline.weight(.medium))
            if case .reverted = assessment {
                Text("USDT не переведены. Сеть могла списать комиссию в ETH.").font(.caption).foregroundStyle(.secondary)
            } else if case .notSeen = assessment {
                Text("Не повторяй перевод, пока не выяснен результат этой попытки.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
            if let checkedAt { Text("Проверено: " + checkedAt.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary) }
            DisclosureGroup("Транзакция и получатель") {
                Text(transfer.txHash).font(.caption2.monospaced()).textSelection(.enabled)
                Text(transfer.intent.recipient).font(.caption2.monospaced()).textSelection(.enabled)
                Link("Открыть в Etherscan", destination: URL(string: "https://etherscan.io/tx/" + transfer.txHash)!)
            }.font(.caption)
        }
        .task(id: "\(transfer.txHash)-\(scenePhase == .active)-\(sectionActive)-\(enabled)") {
            guard enabled, scenePhase == .active, sectionActive else { return }
            while !Task.isCancelled {
                do {
                    let result = try await WalletEVMOutgoingTracker().reconcile(txHash: transfer.txHash, intent: transfer.intent, notBefore: transfer.binding?.addressIssuedAt)
                    guard !Task.isCancelled else { return }
                    assessment = result; error = nil; checkedAt = Date()
                } catch is CancellationError { return }
                catch { self.error = error.localizedDescription }
                do { try await Task.sleep(for: .seconds(12)) } catch { return }
            }
        }
    }
}
