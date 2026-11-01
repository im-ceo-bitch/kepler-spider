import SwiftUI
import UIKit

struct WalletTransferView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var spider: SpiderDevnetStore
    let isRequest: Bool
    let contact: WalletContact
    @State private var amount = ""
    @State private var recipient = ""
    @State private var note = ""
    @State private var isReview = false
    @State private var didSubmit = false
    @State private var transferError: String?

    private var amountIsValid: Bool {
        guard let units = try? SpiderProtocolV1.amountUnits(amount) else { return false }
        return units > 0
    }
    private var validDestination: Bool {
        SpiderDevnetSigner.isValidAddress(recipient.trimmingCharacters(in: .whitespacesAndNewlines)) &&
        recipient.trimmingCharacters(in: .whitespacesAndNewlines) != spider.address
    }
    private var canContinue: Bool {
        amountIsValid && (isRequest || (validDestination && spider.connected &&
            spider.address != nil && spider.pendingForAddress == nil && !spider.sending))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SpyderNavigationButton(symbol: "xmark", label: "Закрыть", action: { dismiss() })
                Spacer()
                Text(isRequest ? "ДЕМО-ЗАПРОС" : "TEST DEVNET")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WalletTheme.secondary)
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    VStack(spacing: 11) {
                        Image(systemName: isRequest ? "arrow.down.left" : "arrow.up.right")
                            .font(.system(size: 27))
                            .frame(width: 70, height: 70)
                            .background(WalletTheme.surface, in: Circle())
                        Text(isRequest ? "Запросить SPD" : "Отправить тестовые SPD")
                            .font(.system(size: 26, weight: .bold))
                        if !contact.id.isEmpty {
                            Text("Контакт: \(contact.name) · адрес нужно ввести отдельно")
                                .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 25)
                    WalletCard {
                        VStack(alignment: .leading, spacing: 14) {
                            if !isRequest {
                                Text("Адрес получателя · Spider Chain")
                                    .font(.system(size: 13, weight: .semibold))
                                TextField("spider1…", text: $recipient)
                                    .font(.system(size: 14, design: .monospaced))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.asciiCapable)
                                    .onChange(of: recipient) { _, _ in isReview = false }
                                Divider()
                            }
                            Text("Сумма · SPD")
                                .font(.system(size: 13, weight: .semibold))
                            TextField("0.000000000", text: $amount)
                                .font(.system(size: 31, weight: .semibold, design: .rounded))
                                .keyboardType(.decimalPad)
                                .onChange(of: amount) { _, _ in isReview = false }
                            Text(isRequest ? "Только просмотр запроса без публикации" :
                                 (spider.connected ? "Доступно: \(spider.balanceText) тестовых SPD" : "Для отправки требуется подключённый Devnet в профиле"))
                                .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                            if isRequest {
                                Divider()
                                TextField("Комментарий (необязательно)", text: $note)
                                    .font(.system(size: 14))
                            }
                        }
                    }
                    if !isRequest, spider.address == nil {
                        Button { spider.deriveAddress() } label: {
                            Label("Открыть SPD-адрес через Face ID", systemImage: "faceid")
                                .font(.system(size: 14, weight: .medium))
                        }.disabled(spider.busy)
                    }
                    if !isRequest, spider.hasConfiguration, !spider.connected, spider.address != nil {
                        Button { Task { await spider.refresh() } } label: {
                            Label("Проверить соединение", systemImage: "arrow.clockwise")
                        }.disabled(spider.refreshing)
                    }
                    if isReview {
                        WalletCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(isRequest ? "Предпросмотр запроса" : "Подтверждение отправки", systemImage: "checkmark.shield")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("\(amount) SPD")
                                    .font(.system(size: 24, weight: .semibold))
                                if !isRequest {
                                    Text(recipient)
                                        .font(.system(size: 12, design: .monospaced))
                                        .textSelection(.enabled)
                                    Text("Сетевая комиссия по текущему контракту: 0.000021 SPD. Отправка подписывается на устройстве после Face ID.")
                                        .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                                } else {
                                    Text("Это только демонстрация. Сетевой запрос не создаётся.")
                                        .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                                }
                            }
                        }
                    }
                    if !isRequest, let pending = spider.pendingForAddress {
                        WalletCard {
                            VStack(alignment: .leading, spacing: 9) {
                                Label(pending.queued ? "В очереди, ещё не подтверждено" : "Статус отправки неизвестен", systemImage: "clock")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(pending.id).font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                Button("Проверить финализацию") { Task { await spider.refresh() } }
                                    .disabled(spider.refreshing)
                                Text("До подтверждения не запускайте повторный перевод с этим nonce.")
                                    .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                            }
                        }
                    }
                    if didSubmit, spider.pendingForAddress == nil, spider.latestConfirmed != nil {
                        Label("Тестовая транзакция финализирована", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundStyle(WalletTheme.ink)
                .padding(20)
            }
            Button {
                if !isReview {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { isReview = true }
                } else if isRequest {
                    dismiss()
                } else {
                    Task {
                        do {
                            try await spider.send(to: recipient, amountText: amount)
                            didSubmit = true
                        } catch { transferError = error.localizedDescription }
                    }
                }
            } label: {
                HStack {
                    if spider.sending { ProgressView().tint(WalletTheme.contrast) }
                    Text(isReview ? (isRequest ? "Закрыть предпросмотр" : "Подписать и отправить в Devnet") : "Продолжить")
                }.spyderPrimaryButton()
            }
            .disabled(!canContinue || didSubmit)
            .opacity((canContinue && !didSubmit) ? 1 : 0.45)
            .padding(.horizontal, 20)
            .padding(.bottom, 25)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .alert("Spider Devnet", isPresented: Binding(
            get: { transferError != nil }, set: { if !$0 { transferError = nil } }
        )) {
            Button("Понятно", role: .cancel) { transferError = nil }
        } message: { Text(transferError ?? "") }
    }
}

/// Verified self-custody receiving. No address from UserDefaults is rendered as a QR:
/// the user must first re-derive it from the protected BIP-39 phrase with system auth.
struct WalletReceiveView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var chains: WalletChainStore
    @EnvironmentObject private var spider: SpiderDevnetStore
    @EnvironmentObject private var assets: WalletPublicAssetsStore
    @EnvironmentObject private var history: WalletActivityStore
    @EnvironmentObject private var access: WalletAccess
    @AppStorage("spyder.wallet.privacyHidden") private var privacyHidden = false
    @State private var selected: WalletReceiveAsset
    @State private var acknowledged = false
    @State private var copied = false
    @State private var depositHash = ""
    @State private var depositChecking = false
    @State private var depositStatus: WalletEVMDepositAssessment?
    @State private var depositError: String?
    @State private var depositGeneration = UUID()

    private var canVerifyERC20: Bool { selected == .usdtERC20 || selected == .usdcERC20 }

    private func resetDepositCheck() {
        depositGeneration = UUID()
        depositStatus = nil
        depositError = nil
        depositChecking = false
    }

    @MainActor
    private func verifyDeposit() async {
        guard let address = verifiedAddress, canVerifyERC20, !depositChecking else { return }
        let generation = UUID()
        depositGeneration = generation
        depositChecking = true
        depositStatus = nil
        depositError = nil
        let token: WalletEVMAsset = selected == .usdtERC20 ? .usdt : .usdc
        let hash = depositHash.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let result = try await WalletEVMDepositVerifier().verify(txHash: hash, recipient: address, token: token)
            guard depositGeneration == generation, verifiedAddress == address,
                  selected == (token == .usdt ? .usdtERC20 : .usdcERC20) else { return }
            depositStatus = result
        } catch {
            guard depositGeneration == generation else { return }
            depositError = error.localizedDescription
        }
        if depositGeneration == generation { depositChecking = false }
    }

    init(preselected: SpyderChain? = .ethereum, tokenTicker: String? = nil) {
        _selected = State(initialValue: WalletReceiveAsset.preselected(chainID: preselected?.rawValue ?? "ethereum", token: tokenTicker))
    }

    private var chain: SpyderChain? {
        switch selected.chainID {
        case "bitcoin": return .bitcoin
        case "ethereum": return .ethereum
        case "solana": return .solana
        default: return nil
        }
    }

    private var verifiedAddress: String? {
        if selected == .spdDevnet { return spider.address }
        guard chains.verifiedForReceiving, chains.verifiedWalletID == access.activeWalletID, let chain,
              let publicAddress = chains.address(for: chain),
              WalletAddressValidator.check(publicAddress, for: chain) == .valid else { return nil }
        return publicAddress
    }

    private var balance: Decimal? {
        if selected == .usdtERC20 || selected == .usdcERC20 { return assets.stablecoins[selected.ticker] }
        guard let chain else { return nil }
        return assets.balances[chain]
    }

    private var receiveEntries: [WalletChainActivity] {
        guard let chain else { return [] }
        return Array((history.activity[chain] ?? [])
            .filter { $0.symbol == selected.ticker && $0.direction == "Получено" }
            .prefix(4))
    }

    private var balanceError: String? {
        if selected == .usdtERC20 || selected == .usdcERC20 { return assets.stablecoinFailures[selected.ticker] }
        guard let chain else { return nil }
        return assets.failures[chain]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Получить криптовалюту")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(access.activeAccountName)
                            .font(.system(size: 13)).foregroundStyle(WalletTheme.secondary)
                    }
                    Spacer()
                    SpyderNavigationButton(symbol: "xmark", label: "Закрыть", action: { dismiss() })
                }
                Text("Выберите актив и точную сеть перевода")
                    .font(.system(size: 13)).foregroundStyle(WalletTheme.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    ForEach(WalletReceiveAsset.supportedMainnet) { item in
                        Button {
                            selected = item
                            acknowledged = false
                            copied = false
                            depositHash = ""
                            resetDepositCheck()
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.ticker).font(.system(size: 16, weight: .bold))
                                    Spacer()
                                    Image(systemName: selected == item ? "checkmark.circle.fill" : "circle")
                                }
                                Text(item.network)
                                    .font(.system(size: 10))
                                    .lineLimit(2)
                                    .foregroundStyle(WalletTheme.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .padding(12)
                            .foregroundStyle(WalletTheme.ink)
                            .background(selected == item ? WalletTheme.canvas : WalletTheme.surface,
                                        in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(
                                selected == item ? WalletTheme.ink : WalletTheme.divider, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }

                WalletCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(selected.network, systemImage: "network.badge.shield.half.filled")
                            .font(.system(size: 13, weight: .semibold))
                        Text(LocalizedStringKey(selected.risk))
                            .font(.system(size: 12))
                            .foregroundStyle(WalletTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if selected != .spdDevnet {
                            Label("Отправка настоящих криптовалют из Spyder Wallet пока отключена. До использования реальных средств проверьте восстановление в совместимом кошельке.", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WalletTheme.ink)
                        }
                        if let contract = selected.contract {
                            Divider()
                            Text("Проверенный контракт · Ethereum")
                                .font(.system(size: 11, weight: .semibold))
                            Text(contract)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(WalletTheme.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                WalletCard {
                    VStack(spacing: 15) {
                        if let address = verifiedAddress {
                            if acknowledged {
                                SpyderQRView(address: address)
                                    .frame(width: 216, height: 216)
                                    .frame(maxWidth: .infinity)
                                    .privacySensitive()
                                Text(address)
                                    .font(.system(size: 13, design: .monospaced))
                                    .multilineTextAlignment(.center)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .privacySensitive()
                                Button {
                                    UIPasteboard.general.setItems([
                                        ["public.utf8-plain-text": address]
                                    ], options: [
                                        .localOnly: true,
                                        .expirationDate: Date().addingTimeInterval(120)
                                    ])
                                    copied = true
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                } label: {
                                    Label(copied ? "Адрес скопирован" : "Скопировать адрес",
                                          systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                                        .spyderPrimaryButton()
                                }
                                .buttonStyle(.plain)
                                Label("Адрес повторно проверен по ключам кошелька", systemImage: "checkmark.shield")
                                    .font(.system(size: 11))
                                    .foregroundStyle(WalletTheme.secondary)
                            } else {
                                Toggle("Я проверил сеть и тип актива. Понимаю, что перевод из другой сети может привести к потере средств.",
                                       isOn: $acknowledged)
                                    .font(.system(size: 13))
                                    .tint(WalletTheme.ink)
                            }
                        } else {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 35))
                                .foregroundStyle(WalletTheme.secondary)
                            Text("Проверить адрес через Face ID или код iPhone")
                                .font(.system(size: 13))
                                .multilineTextAlignment(.center)
                            Button {
                                if selected == .spdDevnet { spider.deriveAddress() }
                                else { chains.activate() }
                            } label: {
                                HStack(spacing: 9) {
                                    if chains.isLoading || spider.busy { ProgressView().tint(WalletTheme.contrast) }
                                    Label("Проверить адрес", systemImage: "faceid")
                                }
                                .spyderPrimaryButton()
                            }
                            .buttonStyle(.plain)
                            .disabled(chains.isLoading || spider.busy)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if selected != .spdDevnet, verifiedAddress != nil {
                    WalletCard {
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                Text("Баланс и зачисления").font(.system(size: 15, weight: .semibold))
                                Spacer()
                                if assets.loading { ProgressView() }
                            }
                            Text(privacyHidden ? "••••" : (balance.map {
                                WalletPublicAssetsStore.formatted($0, fractionDigits: 6) + " " + selected.ticker
                            } ?? "— " + selected.ticker))
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            if let updated = assets.updatedAt {
                                Text("Обновлено: " + updated.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 11)).foregroundStyle(WalletTheme.secondary)
                            }
                            if let balanceError {
                                Label("Ошибка сети: " + balanceError, systemImage: "wifi.exclamationmark")
                                    .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                            }
                            Divider()
                            Text("Последние входящие операции").font(.system(size: 13, weight: .semibold))
                            if receiveEntries.isEmpty {
                                Text("Нет обнаруженных зачислений. Сведения провайдера могут поступать с задержкой.")
                                    .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                            }
                            ForEach(receiveEntries) { entry in
                                Link(destination: entry.explorerURL) {
                                    HStack {
                                        Image(systemName: entry.state == .confirmed ? "checkmark.circle" : "clock")
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(canVerifyERC20 ? "Найдено индексатором · проверьте RPC" :
                                                (entry.state == .confirmed ? "Подтверждено" : "Ожидает подтверждения"))
                                            Text(String(entry.hash.prefix(10)) + "…")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(WalletTheme.secondary)
                                        }
                                        Spacer()
                                        Text(privacyHidden ? "••••" : entry.amount.map {
                                            WalletPublicAssetsStore.formatted($0, fractionDigits: 6) + " " + selected.ticker
                                        } ?? "—")
                                    }
                                    .font(.system(size: 12))
                                    .foregroundStyle(WalletTheme.ink)
                                }
                            }
                            if canVerifyERC20, let first = receiveEntries.first {
                                Button {
                                    depositHash = first.hash
                                    resetDepositCheck()
                                    Task { await verifyDeposit() }
                                } label: {
                                    Label("Проверить последнее зачисление через Ethereum RPC", systemImage: "checkmark.shield")
                                        .font(.system(size: 12, weight: .medium))
                                }
                            }
                            Button { Task { await refreshNetwork() } } label: {
                                Label("Обновить зачисления", systemImage: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .disabled(assets.loading)
                        }
                    }
                }
                if canVerifyERC20, verifiedAddress != nil {
                    WalletCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Проверить ERC-20 зачисление", systemImage: "checkmark.shield")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Вставьте хеш операции из отправляющего кошелька. Проверка сверяет контракт токена, ваш адрес, квитанцию и подтверждения через Ethereum RPC.")
                                .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                            TextField("0x… хеш транзакции", text: $depositHash)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(size: 12, design: .monospaced))
                                .onChange(of: depositHash) { _, _ in resetDepositCheck() }
                            Button { Task { await verifyDeposit() } } label: {
                                HStack(spacing: 8) {
                                    if depositChecking { ProgressView() }
                                    Label("Проверить по блокчейну", systemImage: "network")
                                }
                                .spyderPrimaryButton()
                            }
                            .buttonStyle(.plain)
                            .disabled(depositChecking || depositHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if let depositStatus {
                                switch depositStatus {
                                case .notMined:
                                    Label("Квитанция пока не найдена. Транзакция может ожидать включения в блок или отсутствовать.", systemImage: "clock")
                                        .foregroundStyle(.orange)
                                case .observed(let result, let providers):
                                    Label("Обнаружено: \(result.amountText) \(result.token.rawValue) · \(result.confirmations) подтверждений · \(providers) RPC. Независимое подтверждение пока не получено.", systemImage: "clock.badge.checkmark")
                                        .foregroundStyle(.orange)
                                case .independentlyConfirmed(let result):
                                    Label("Проверено двумя RPC: \(result.amountText) \(result.token.rawValue) · минимум \(result.confirmations) подтверждений.", systemImage: "checkmark.shield.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            if let depositError {
                                Label(depositError, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                            Text("Проверка RPC не гарантирует окончательность транзакции и не означает готовность кошелька к реальным переводам.")
                                .font(.system(size: 11)).foregroundStyle(WalletTheme.secondary)
                        }
                        .font(.system(size: 12))
                    }
                }
                Text("Проверка адреса не равна аудиту кошелька. Перед значительным переводом выполните минимальный тест, дождитесь подтверждений и проверьте доступность восстановления и отправки средств.")
                    .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                DisclosureGroup("Тестовая сеть Spider Chain") {
                    Button {
                        selected = .spdDevnet
                        acknowledged = false
                        copied = false
                    } label: { Label("SPD · Devnet (не реальные средства)", systemImage: "network") }
                }
                .font(.system(size: 12))
                .foregroundStyle(WalletTheme.secondary)
            }
            .foregroundStyle(WalletTheme.ink)
            .padding(20)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 30)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .onChange(of: access.activeWalletID) { _, _ in
            acknowledged = false
            copied = false
            depositHash = ""
            resetDepositCheck()
        }
        .task(id: verifiedAddress) {
            guard selected != .spdDevnet, verifiedAddress != nil else { return }
            await refreshNetwork()
            while !Task.isCancelled && scenePhase == .active {
                do { try await Task.sleep(nanoseconds: 45_000_000_000) }
                catch { break }
                guard !Task.isCancelled && scenePhase == .active else { break }
                await refreshNetwork()
            }
        }
        .alert("Ошибка получения адресов", isPresented: Binding(
            get: { chains.errorMessage != nil },
            set: { if !$0 { chains.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { chains.errorMessage = nil }
        } message: { Text(chains.errorMessage ?? "") }
    }

    private func refreshNetwork() async {
        let publicAddresses = chains.addresses
        guard chains.verifiedForReceiving, chains.verifiedWalletID == access.activeWalletID,
              !publicAddresses.isEmpty else { return }
        async let balances: Void = assets.refresh(addresses: publicAddresses)
        async let incoming: Void = history.refresh(addresses: publicAddresses)
        _ = await (balances, incoming)
    }
}
