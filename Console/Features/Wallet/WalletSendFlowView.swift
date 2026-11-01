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
    @EnvironmentObject private var addressBook: WalletAddressBookStore
    @State private var selected: SpyderChain = .ethereum
    @State private var evmAsset: WalletEVMAsset = .eth
    @State private var evmQuote: WalletEVMQuote?
    @State private var quoteLoading = false
    @State private var quoteError: String?
    @State private var quoteGeneration = UUID()
    @State private var recipient = ""
    @State private var amount = ""
    @State private var reviewing = false
    @State private var showUnavailable = false
    @State private var showAddressBook = false
    @State private var showSaveRecipient = false
    let preselected: SpyderChain?

    init(preselected: SpyderChain? = nil) { self.preselected = preselected }

    private var normalizedRecipient: String { recipient.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var parsedAmount: Decimal? {
        let raw = amount.replacingOccurrences(of: ",", with: ".")
        guard raw.range(of: "^[0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil,
              let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")),
              value > 0 else { return nil }
        let decimals = raw.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
        let allowed = selected == .ethereum ? evmAsset.decimals : selected == .solana ? 9 : 8
        return decimals <= allowed ? value : nil
    }
    private var recipientValid: Bool { WalletAddressValidator.check(normalizedRecipient, for: selected) == .valid }
    private var validToReview: Bool {
        guard recipientValid, normalizedRecipient.caseInsensitiveCompare(chains.address(for: selected) ?? "") != .orderedSame,
              let entered = parsedAmount else { return false }
        if selected == .ethereum, evmAsset != .eth {
            return assets.stablecoins[evmAsset.rawValue].map { entered <= $0 } ?? false
        }
        return assets.balances[selected].map { entered <= $0 } ?? false
    }

    private func clearQuote() {
        quoteGeneration = UUID()
        evmQuote = nil
        quoteLoading = false
        quoteError = nil
        reviewing = false
    }

    private func prepareReview() {
        guard validToReview else { return }
        guard selected == .ethereum else {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { reviewing = true }
            return
        }
        guard let sender = chains.address(for: .ethereum) else {
            quoteError = "Не удалось получить адрес Ethereum. Разблокируйте кошелёк."
            return
        }
        let currentGeneration = UUID()
        quoteGeneration = currentGeneration
        quoteLoading = true
        quoteError = nil
        let to = normalizedRecipient
        let entered = amount.replacingOccurrences(of: ",", with: ".")
        let asset = evmAsset
        Task {
            do {
                let prepared = try await WalletEVMPreflightClient().quote(
                    sender: sender, recipient: to, amount: entered, asset: asset)
                guard quoteGeneration == currentGeneration,
                      chains.address(for: .ethereum)?.caseInsensitiveCompare(sender) == .orderedSame else { return }
                evmQuote = prepared
                reviewing = true
                UISelectionFeedbackGenerator().selectionChanged()
            } catch {
                guard quoteGeneration == currentGeneration else { return }
                quoteError = error.localizedDescription
                evmQuote = nil
                reviewing = false
            }
            if quoteGeneration == currentGeneration { quoteLoading = false }
        }
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
                            .onChange(of: selected) { _, _ in
                                clearQuote(); evmAsset = .eth; amount = ""
                            }
                            if selected == .ethereum {
                                Picker("Монета Ethereum", selection: $evmAsset) {
                                    ForEach(WalletEVMAsset.allCases) { asset in
                                        Text(asset.rawValue).tag(asset)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: evmAsset) { _, _ in clearQuote(); amount = "" }
                                Text(evmAsset == .eth ? "Нативная монета Ethereum Mainnet" : "ERC-20 · сеть Ethereum Mainnet")
                                    .font(.caption).foregroundStyle(WalletTheme.secondary)
                            }
                            Divider()
                            Text("Адрес получателя").font(.system(size: 14, weight: .semibold))
                            TextField("Вставить адрес", text: $recipient)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.none)
                                .font(.system(size: 14, design: .monospaced))
                                .onChange(of: recipient) { _, _ in clearQuote() }
                            HStack(spacing: 16) {
                                Button {
                                    if let text = UIPasteboard.general.string { recipient = text }
                                } label: { Label("Вставить", systemImage: "doc.on.clipboard") }
                                Button { showAddressBook = true } label: { Label("Получатели", systemImage: "person.crop.rectangle.stack") }
                                if recipientValid {
                                    Button { showSaveRecipient = true } label: { Label("Сохранить", systemImage: "bookmark") }
                                }
                            }
                            .font(.footnote)
                            if !recipient.isEmpty && !recipientValid {
                                if case .invalid(let detail) = WalletAddressValidator.check(recipient, for: selected) {
                                    Label(detail, systemImage: "exclamationmark.triangle")
                                        .font(.footnote).foregroundStyle(.orange)
                                }
                            }
                            Divider()
                            Text("Сумма \(selected == .ethereum ? evmAsset.rawValue : selected.ticker)").font(.system(size: 14, weight: .semibold))
                            TextField("0.00", text: $amount)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 28, weight: .medium, design: .rounded))
                                .onChange(of: amount) { _, _ in clearQuote() }
                            Text("Баланс: " + ((selected == .ethereum && evmAsset != .eth
                                ? assets.stablecoins[evmAsset.rawValue] : assets.balances[selected]).map {
                                WalletPublicAssetsStore.formatted($0) + " " +
                                (selected == .ethereum ? evmAsset.rawValue : selected.ticker)
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
                                Text("Сумма: \(amount) \(selected == .ethereum ? evmAsset.rawValue : selected.ticker)")
                                    .font(.system(size: 20, weight: .medium))
                                Text(normalizedRecipient)
                                    .font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled)
                                Divider()
                                if let quote = evmQuote, selected == .ethereum {
                                    Label("Проверено по Ethereum Mainnet", systemImage: "checkmark.shield")
                                        .font(.subheadline).foregroundStyle(.green)
                                    Text("Макс. комиссия: \(quote.maxFeeETH) ETH")
                                    Text("Gas limit: \(quote.gasLimit) · Pending nonce: \(quote.nonce)")
                                    Text("RPC: \(quote.provider) · данные на момент проверки")
                                        .font(.caption).foregroundStyle(WalletTheme.secondary)
                                    Text("Комиссия приблизительная: сеть может изменить её до включения транзакции в блок.")
                                        .font(.caption).foregroundStyle(WalletTheme.secondary)
                                } else {
                                    Label("Сетевая комиссия не рассчитана", systemImage: "exclamationmark.shield")
                                        .font(.footnote).foregroundStyle(.orange)
                                }
                                Text("Это предварительный расчёт, а не отправка. Подпись и публикация Mainnet-транзакций пока отключены.")
                                    .font(.footnote).foregroundStyle(WalletTheme.secondary)
                                if selected == .ethereum {
                                    Text("Адрес проверен по формату, но EIP-55 checksum пока не проверяется. Перед отправкой сверяйте его с получателем.")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    if let quoteError {
                        Label(quoteError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                    Label("Никогда не вставляйте сюда seed-фразу или приватный ключ. Нужен только публичный адрес получателя.", systemImage: "lock.shield")
                        .font(.footnote).foregroundStyle(WalletTheme.secondary)
                }
                .foregroundStyle(WalletTheme.ink)
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if !reviewing { prepareReview() }
                    else { showUnavailable = true }
                } label: {
                    Label(LocalizedStringKey(quoteLoading ? "Проверка сети…" : reviewing ? "Отправка пока недоступна" : "Проверить перевод"), systemImage: reviewing ? "lock.shield" : "arrow.right")
                        .spyderPrimaryButton()
                }
                .buttonStyle(.plain)
                .disabled(!validToReview || quoteLoading)
                .opacity(validToReview && !quoteLoading ? 1 : 0.45)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(WalletTheme.canvas)
            }
            .background(WalletTheme.canvas.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Закрыть") { dismiss() } } }
        }
        .onAppear { if let preselected { selected = preselected } }
        .sheet(isPresented: $showAddressBook) {
            WalletAddressBookView(onSelect: { entry in
                selected = entry.chain
                clearQuote()
                evmAsset = .eth
                recipient = entry.address
                amount = ""
            })
        }
        .sheet(isPresented: $showSaveRecipient) {
            WalletAddressBookAddView(chain: selected, address: normalizedRecipient)
        }
        .alert("Отправка ещё не включена", isPresented: $showUnavailable) {
            Button("Понятно", role: .cancel) { }
        } message: {
            Text("Вы не отправили средства. Подпись и публикация Mainnet-транзакций станут доступны после прохождения криптографических и сетевых тестов.")
        }
    }
}
