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
    @State private var retryCount = 0
    @State private var checking = false

    private var hasFinalResult: Bool {
        switch assessment {
        case .confirmed, .reverted: return true
        default: return false
        }
    }

    private var status: LocalizedStringKey {
        switch assessment {
        case .confirmed: return outgoing ? "Перевод подтверждён в Ethereum" : "Получено в Ethereum"
        case .reverted: return "Транзакция завершилась ошибкой"
        case .observed(let proof, let providers): return "В блоке · \(String(proof.confirmations)) подтверждений · \(String(providers))/2 источников"
        case .pending: return "Ожидает включения в блок"
        case .notSeen: return "Результат отправки пока неизвестен"
        case nil: return error == nil ? "Проверяем транзакцию…" : "Проверка сети недоступна"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: outgoing ? "arrow.up.right" : "arrow.down.left")
                    .font(.headline).frame(width: 36, height: 36)
                    .background(.primary.opacity(0.08), in: Circle())
                    .accessibilityLabel(outgoing ? "Исходящий перевод" : "Входящий перевод")
                VStack(alignment: .leading, spacing: 3) {
                    Text(transfer.intent.amount + " USDT")
                        .font(.title3.weight(.semibold)).monospacedDigit()
                    Text("Ethereum · ERC-20").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(status)
                .font(.subheadline.weight(.medium))
                .accessibilityAddTraits(.updatesFrequently)
            if case .reverted = assessment {
                Text("USDT не переведены. Сеть могла списать комиссию в ETH.").font(.caption).foregroundStyle(.secondary)
            } else if case .notSeen = assessment {
                Text("Не повторяй перевод, пока не выяснен результат этой попытки.").font(.caption).foregroundStyle(.secondary)
            }
            if let error {
                Label("Не удалось обновить статус: " + error, systemImage: "wifi.exclamationmark")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Повторить проверку") { retryCount += 1 }
                    .buttonStyle(SpyderActionButtonStyle(.tertiary))
                    .disabled(!enabled || scenePhase != .active || !sectionActive || checking)
            } else if !hasFinalResult {
                Button { retryCount += 1 } label: {
                    HStack(spacing: 8) {
                        if checking { ProgressView() }
                        Text(checking ? "Проверяем статус…" : "Обновить статус")
                    }
                }
                    .buttonStyle(SpyderActionButtonStyle(.tertiary))
                    .disabled(!enabled || scenePhase != .active || !sectionActive || checking)
                    .accessibilityHint("Проверить хеш в сети повторно, без повторной отправки средств")
            }
            if let checkedAt {
                Text("Проверено в \(checkedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Детали перевода") {
                VStack(alignment: .leading, spacing: 10) {
                    detail("Хеш транзакции", value: transfer.txHash)
                    detail("Адрес получателя", value: transfer.intent.recipient)
                    if let url = URL(string: "https://etherscan.io/tx/" + transfer.txHash) {
                        Link(destination: url) {
                            Label("Открыть в Etherscan", systemImage: "arrow.up.right.square")
                        }.frame(minHeight: 44)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }.font(.subheadline).tint(.primary)
        }
        .task(id: "\(transfer.txHash)-\(scenePhase == .active)-\(sectionActive)-\(enabled)-\(retryCount)") {
            guard enabled, scenePhase == .active, sectionActive else { return }
            defer { checking = false }
            while !Task.isCancelled {
                checking = true
                do {
                    let result = try await WalletEVMOutgoingTracker().reconcile(txHash: transfer.txHash, intent: transfer.intent, notBefore: transfer.binding?.addressIssuedAt)
                    guard !Task.isCancelled else { return }
                    assessment = result; error = nil; checkedAt = Date()
                } catch is CancellationError { return }
                catch { self.error = error.localizedDescription }
                checking = false
                do { try await Task.sleep(for: .seconds(12)) } catch { return }
            }
        }
    }

    private func detail(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.caption.monospaced()).textSelection(.enabled)
        }
    }
}
