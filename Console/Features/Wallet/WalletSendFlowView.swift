import SwiftUI
import UIKit

/// UX / validation foundation for native mainnet transfers.
/// A real broadcast is intentionally unavailable until per-chain signing, replay
/// protection, UTXO selection, RPC failover, and automated transaction tests pass.
/// Never show a fake tx hash or pretend that a transfer was submitted.
struct WalletSendFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var chains: WalletChainStore
    @EnvironmentObject private var assets: WalletPublicAssetsStore
    @State private var selected: SpyderChain = .ethereum
    @State private var recipient = ""
    @State private var amount = ""
    @State private var reviewing = false
    @State private var showUnavailable = false
    @State private var observedError: String?
    @State private var checkmark = false
    let preselected: SpyderChain?

    init(preselected: SpyderChain? = nil) { self.preselected = preselected }

    private var normalizedRecipient: String { recipient.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var parsedAmount: Decimal? {
        let raw = amount.replacingOccurrences(of: ",", with: ".")
        guard raw.range(of: "^[0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil,
              let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")),
              value > 0 else { return nil }
        let decimals = raw.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
        let allowed = selected == .ethereum ? 18 : selected == .solana ? 9 : 8
        return decimals <= allowed ? value : nil
    }
    private var recipientValid: Bool {
        switch selected {
        case .ethereum:
            return normalizedRecipient.range(of: "^0x[0-9a-fA-F]{40}$", options: .regularExpression) != nil
        case .solana:
            return (32...44).contains(normalizedRecipient.count) &&
                normalizedRecipient.range(of: "^[1-9A-HJ-NP-Za-km-z]+$", options: .regularExpression) != nil
        case .bitcoin:
            return normalizedRecipient.range(of: "^bc1[ac-hj-np-z02-9]{38,87}$", options: .regularExpression) != nil
        }
    }
    private var validToReview: Bool {
        recipientValid && normalizedRecipient != chains.address(for: selected) && parsedAmount != nil &&
        (assets.balances[selected].map { (parsedAmount ?? 0) <= $0 } ?? false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label(LocalizedStringKey(reviewing ? "Проверка перевода" : "Отправить криптовалюту"), systemImage: reviewing ? "checkmark.shield" : "arrow.up.right")
                        .font(.system(size: 28, weight: .bold))
                        .symbolEffect(.bounce, value: reviewing)
                    Text("Подготовка транзакции Mainnet · неподписанная")
                        .font(.subheadline).foregroundStyle(WalletTheme.secondary)
                    WalletCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Актив и сеть").font(.system(size: 14, weight: .semibold))
                            Picker("Актив", selection: $selected) {
                                ForEach(SpyderChain.allCases) { chain in
                                    Label(chain.name + " · " + chain.ticker, systemImage: chain.symbol).tag(chain)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: selected) { _, _ in reviewing = false; recipient = ""; amount = "" }
                            Divider()
                            Text("Адрес получателя").font(.system(size: 14, weight: .semibold))
                            TextField("Вставить адрес", text: $recipient)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.none)
                                .font(.system(size: 14, design: .monospaced))
                                .onChange(of: recipient) { _, _ in reviewing = false }
                            Button {
                                if let text = UIPasteboard.general.string { recipient = text }
                            } label: { Label("Вставить адрес", systemImage: "doc.on.clipboard") }
                                .font(.footnote)
                            if !recipient.isEmpty && !recipientValid {
                                Label("Проверь адрес и выбранную сеть", systemImage: "exclamationmark.triangle")
                                    .font(.footnote).foregroundStyle(.orange)
                            }
                            Divider()
                            Text("Сумма \(selected.ticker)").font(.system(size: 14, weight: .semibold))
                            TextField("0.00", text: $amount)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 28, weight: .medium, design: .rounded))
                                .onChange(of: amount) { _, _ in reviewing = false }
                            Text("Баланс: " + (assets.balances[selected].map {
                                WalletPublicAssetsStore.formatted($0) + " " + selected.ticker
                            } ?? "нет данных"))
                                .font(.footnote).foregroundStyle(WalletTheme.secondary)
                        }
                    }
                    if reviewing {
                        WalletCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Проверь реквизиты", systemImage: "checkmark.shield")
                                    .font(.system(size: 17, weight: .semibold))
                                Text("Сеть: \(selected.name)")
                                Text("Сумма: \(amount) \(selected.ticker)")
                                    .font(.system(size: 20, weight: .medium))
                                Text(normalizedRecipient)
                                    .font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled)
                                Divider()
                                Label("Сетевая комиссия не рассчитана", systemImage: "exclamationmark.shield")
                                    .font(.footnote).foregroundStyle(.orange)
                                Text("Для реальной отправки нужны проверенные комиссии, подпись на устройстве и надёжная отправка в сеть. Эти компоненты пока не готовы.")
                                    .font(.footnote).foregroundStyle(WalletTheme.secondary)
                            }
                        }
                    }
                    Label("Никогда не вставляй сюда сид-фразу или приватный ключ. Требуется только публичный адрес получателя.", systemImage: "lock.shield")
                        .font(.footnote).foregroundStyle(WalletTheme.secondary)
                }
                .foregroundStyle(WalletTheme.ink)
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if !reviewing {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { reviewing = true }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } else { showUnavailable = true }
                } label: {
                    Label(LocalizedStringKey(reviewing ? "Отправка пока недоступна" : "Проверить перевод"), systemImage: reviewing ? "lock.shield" : "arrow.right")
                        .spyderPrimaryButton()
                }
                .buttonStyle(.plain)
                .disabled(!validToReview)
                .opacity(validToReview ? 1 : 0.45)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(WalletTheme.canvas)
            }
            .background(WalletTheme.canvas.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Закрыть") { dismiss() } } }
        }
        .onAppear { if let preselected { selected = preselected } }
        .alert("Отправка ещё не включена", isPresented: $showUnavailable) {
            Button("Понятно", role: .cancel) { }
        } message: {
            Text("Вы не отправили средства. Подпись и публикация Mainnet-транзакций станут доступны после прохождения криптографических и сетевых тестов.")
        }
    }
}
