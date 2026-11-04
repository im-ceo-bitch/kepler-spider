import SwiftUI
import UIKit

/// Reviewed USDT ERC-20 chat transfers use the isolated signer and durable publication service.
/// ETH/USDC and generic manual-address sends remain read-only previews.
struct WalletSendFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var transfers: WalletUSDTTransferStore
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var access: WalletAccess
    @EnvironmentObject private var chat: SpyderChatStore
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
    @State private var confirmUSDT = false
    @State private var approvedWalletID: String?
    @State private var submitted: WalletUSDTTransferRecord?
    @State private var pageVisible = false
    @State private var showAddressBook = false
    @State private var showSaveRecipient = false
    let preselected: SpyderChain?
    let chatRecipient: SpyderChatRecipient?

    init(preselected: SpyderChain? = nil) { self.preselected = preselected; self.chatRecipient = nil }
    init(chatRecipient: SpyderChatRecipient) { self.preselected = .ethereum; self.chatRecipient = chatRecipient }

    private var recipientContextValid: Bool {
        guard let context = chatRecipient else { return true }
        guard access.unlocked, chat.activePersonaID == context.ownerID,
              context.payment.isValid(), selected == .ethereum, evmAsset == context.payment.asset.evmAsset,
              normalizedRecipient == context.payment.address else { return false }
        return SpyderPaymentEnvelope.recipient(in: chat.messageByPeer[context.peerID] ?? [],
            peer: context.peerID, owner: context.ownerID, asset: context.payment.asset) == context.payment
    }

    private var canSendUSDT: Bool {
        guard let context = chatRecipient, context.payment.asset == .usdtEthereum,
              selected == .ethereum, evmAsset == .usdt, approvedWalletID == access.activeWalletID,
              let quote = evmQuote, quote.matches(sender: chains.address(for: .ethereum) ?? "",
                recipient: normalizedRecipient, amount: amount.replacingOccurrences(of: ",", with: "."), asset: .usdt),
              recipientContextValid, submitted == nil else { return false }
        return WalletEthereumSignature.verifyOwnership(context.payment, requester: context.ownerID,
            receiver: context.peerID, server: chat.serverAddress)
    }

    private var primaryButtonTitle: String {
        if transfers.busy { return "Подтверждение и отправка…" }
        if submitted != nil { return "Вернуться в чат" }
        if quoteLoading { return "Проверка сети…" }
        if reviewing { return canSendUSDT ? "Подтвердить и отправить USDT" : "Обновить реквизиты или расчёт" }
        return "Проверить перевод"
    }

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
        guard recipientContextValid, recipientValid, normalizedRecipient.caseInsensitiveCompare(chains.address(for: selected) ?? "") != .orderedSame,
              let entered = parsedAmount else { return false }
        if selected == .ethereum, evmAsset != .eth {
            return assets.stablecoins[evmAsset.rawValue].map { entered <= $0 } ?? false
        }
        return assets.balances[selected].map { entered <= $0 } ?? false
    }

    private func clearQuote() {
        if transfers.busy { transfers.cancelAuthorization() }
        quoteGeneration = UUID()
        evmQuote = nil
        quoteLoading = false
        quoteError = nil
        reviewing = false
        approvedWalletID = nil
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
        let walletID = access.activeWalletID
        Task {
            defer { if quoteGeneration == currentGeneration { quoteLoading = false } }
            do {
                let prepared = try await WalletEVMPreflightClient().quote(
                    sender: sender, recipient: to, amount: entered, asset: asset)
                guard quoteGeneration == currentGeneration, recipientContextValid, access.activeWalletID == walletID,
                      chains.address(for: .ethereum)?.caseInsensitiveCompare(sender) == .orderedSame else { return }
                evmQuote = prepared
                approvedWalletID = walletID
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
                    Text(chatRecipient == nil ? "Подготовка транзакции Mainnet · неподписанная" : "Собеседник выбран в чате · подготовка перевода")
                        .font(.subheadline).foregroundStyle(WalletTheme.secondary)
                    WalletCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Актив и сеть").font(.system(size: 14, weight: .semibold))
                            if let context = chatRecipient {
                                Text(context.payment.asset.ticker + " · " + context.payment.asset.network)
                                    .font(.headline)
                            } else {
                            Picker("Актив", selection: $selected) {
                                ForEach(SpyderChain.allCases) { chain in
                                    Label(chain.name + " · " + chain.ticker, systemImage: chain.symbol).tag(chain)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: selected) { _, _ in
                                clearQuote(); evmAsset = chatRecipient?.payment.asset.evmAsset ?? .eth; amount = ""
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
                            }
                            Divider()
                            if let context = chatRecipient {
                                Text("Получатель").font(.system(size: 14, weight: .semibold))
                                Text(context.name).font(.headline)
                                Text(context.handle).font(.subheadline).foregroundStyle(WalletTheme.secondary)
                                DisclosureGroup("Адрес из защищённого чата") {
                                    Text(normalizedRecipient).font(.footnote.monospaced()).textSelection(.enabled)
                                }
                                if !recipientContextValid {
                                    Text("Реквизиты изменились, истекли или личность переключена. Запроси их заново в чате.")
                                        .font(.footnote).foregroundStyle(.red)
                                }
                            } else {
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
                                Text(chatRecipient?.payment.asset == .usdtEthereum
                                    ? "После подтверждения сумма и получатель будут подписаны на этом устройстве. Перевод необратим; комиссия списывается в ETH."
                                    : "Для этого актива доступна только подготовка. Подпись и публикация пока отключены.")
                                    .font(.footnote).foregroundStyle(WalletTheme.secondary)
                                if selected == .ethereum {
                                    Text("Адрес проверен по формату, но EIP-55 checksum пока не проверяется. Перед отправкой сверяйте его с получателем.")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    if let submitted {
                        WalletCard {
                            SpyderTransferStatusView(transfer: SpyderTransferEnvelope(requestID: submitted.requestID,
                                txHash: submitted.txHash, intent: submitted.intent, submittedAt: submitted.submittedAt, binding: submitted.binding, authorizationSignature: submitted.authorizationSignature))
                        }
                        Text("Попытка сохранена. Статус проверяется по хешу; повторная отправка автоматически не выполняется.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let error = transfers.error { Text(error).font(.footnote).foregroundStyle(.red) }
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
                .disabled(transfers.busy || submitted != nil)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if submitted != nil { dismiss() }
                    else if !reviewing { prepareReview() }
                    else if canSendUSDT { confirmUSDT = true }
                    else if chatRecipient?.payment.asset == .usdtEthereum && recipientContextValid { clearQuote(); prepareReview() }
                    else { showUnavailable = true }
                } label: {
                    Label(LocalizedStringKey(primaryButtonTitle), systemImage: reviewing ? "lock.shield" : "arrow.right")
                        .spyderPrimaryButton()
                }
                .buttonStyle(.plain)
                .disabled(transfers.busy || (submitted == nil && (!validToReview || quoteLoading)))
                .opacity(submitted != nil || (validToReview && !quoteLoading) ? 1 : 0.45)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(WalletTheme.canvas)
            }
            .background(WalletTheme.canvas.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Закрыть") { dismiss() }.disabled(transfers.busy) } }
        }
        .interactiveDismissDisabled(transfers.busy)
        .onDisappear { pageVisible = false; transfers.cancelAuthorization() }
        .onAppear {
            pageVisible = true
            if let preselected { selected = preselected }
            if let context = chatRecipient {
                selected = .ethereum; evmAsset = context.payment.asset.evmAsset
                recipient = context.payment.address ?? ""
            }
        }
        .task {
            guard chatRecipient != nil else { return }
            while !Task.isCancelled {
                if !recipientContextValid && (reviewing || quoteLoading) { clearQuote() }
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
        .onChange(of: access.activeWalletID) { _, _ in clearQuote() }
        .onChange(of: chat.activePersonaID) { _, _ in if chatRecipient != nil { clearQuote() } }
        .confirmationDialog("Отправить USDT в Ethereum?", isPresented: $confirmUSDT, titleVisibility: .visible) {
            Button("Подтвердить через Face ID / код") { sendUSDT() }
        } message: {
            Text("\(amount) USDT → \(chatRecipient?.name ?? "")\n\(normalizedRecipient)\nМаксимальная комиссия: \(evmQuote?.maxFeeETH ?? "") ETH")
        }
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
            Text("Если это USDT, заново запроси подписанные реквизиты и обнови расчёт комиссии. ETH и USDC пока не отправляются из этого экрана. Вы не отправили средства. Для продолжения нужны действующие реквизиты и свежий расчёт.")
        }
    }
    private func sendUSDT() {
        guard canSendUSDT, !transfers.busy, let quote = evmQuote, let recipient = chatRecipient,
              let sender = chains.address(for: .ethereum) else { return }
        let walletID = access.activeWalletID, server = chat.serverAddress
        do {
            let intent = try WalletEVMUnsignedIntent(quote: quote, expectedSender: sender)
            Task {
                let result = await transfers.send(intent: intent, quote: quote, walletID: walletID,
                    recipient: recipient, server: server, authorize: {
                        pageVisible && scenePhase == .active && access.unlocked &&
                        access.activeWalletID == walletID && chat.serverAddress == server && recipientContextValid &&
                        reviewing && evmQuote == quote && approvedWalletID == walletID
                    })
                submitted = result ?? transfers.records.first(where: { $0.walletID == walletID && $0.intent == intent })
                if submitted != nil {
                    await transfers.announce(chat: chat)
                    await assets.refresh(addresses: chains.addresses)
                }
                else { clearQuote() }
            }
        } catch { quoteError = error.localizedDescription; reviewing = false }
    }

}
