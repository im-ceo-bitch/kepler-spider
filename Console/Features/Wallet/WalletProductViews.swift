import SwiftUI
import UIKit

/// Non-custodial account management. Only display names are persisted in preferences.
/// Each account's BIP-39 phrase is stored independently in access-controlled Keychain.
struct WalletAccountsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var access: WalletAccess
    @EnvironmentObject private var chains: WalletChainStore
    @EnvironmentObject private var assets: WalletPublicAssetsStore
    @EnvironmentObject private var history: WalletActivityStore
    @State private var rename = ""
    @State private var showingRename = false
    @State private var showingNew = false

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Ваши кошельки", systemImage: "wallet.pass")
                        .font(.system(size: 30, weight: .bold))
                    Text("Каждый кошелёк имеет отдельную фразу восстановления. При переключении меняются адреса и баланс.")
                        .font(.subheadline).foregroundStyle(WalletTheme.secondary)
                    WalletCard {
                        VStack(spacing: 7) {
                            ForEach(access.accounts) { account in
                                Button {
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                                        access.switchAccount(account.id)
                                        chains.selectAccount(account.id)
                                        assets.resetForAccountChange()
                                        history.clear()
                                    }
                                    dismiss()
                                } label: {
                                    HStack(spacing: 13) {
                                        Image(systemName: "wallet.bifold")
                                            .font(.system(size: 19))
                                            .frame(width: 42, height: 42)
                                            .background(WalletTheme.canvas, in: RoundedRectangle(cornerRadius: 13))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(account.name).font(.system(size: 16, weight: .semibold))
                                            Text(account.id == WalletVault.legacyID ? "Локальный кошелёк" : "Отдельная фраза BIP-39")
                                                .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                                        }
                                        Spacer()
                                        if access.activeWalletID == account.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .symbolEffect(.bounce, value: access.activeWalletID)
                                        } else { Image(systemName: "chevron.right").foregroundStyle(WalletTheme.secondary) }
                                    }
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                if account.id != access.accounts.last?.id { Divider() }
                            }
                        }
                    }
                    Button {
                        rename = access.activeAccountName
                        showingRename = true
                    } label: { Label("Переименовать активный кошелёк", systemImage: "pencil") }
                        .font(.system(size: 15, weight: .semibold))
                    Button { showingNew = true } label: {
                        Label("Создать или импортировать кошелёк", systemImage: "plus.circle.fill")
                            .spyderPrimaryButton()
                    }
                    .buttonStyle(.plain)
                    Text("Новые кошельки хранятся в локальном Keychain. Резервная копия одного кошелька не восстанавливает другие.")
                        .font(.footnote).foregroundStyle(WalletTheme.secondary)
                }
                .padding(22)
            }
            .foregroundStyle(WalletTheme.ink)
            .background(WalletTheme.canvas.ignoresSafeArea())
            .navigationTitle("Мои кошельки")
            .alert("Название кошелька", isPresented: $showingRename) {
                TextField("Название", text: $rename)
                Button("Сохранить") { access.renameActive(rename) }
                Button("Отмена", role: .cancel) { }
            } message: { Text("Название видно только на этом устройстве.") }
        .fullScreenCover(isPresented: $showingNew) {
            WalletOnboardingView(isAddingAccount: true, onComplete: {
                showingNew = false
                chains.selectAccount(access.activeWalletID)
                assets.resetForAccountChange()
                history.clear()
                dismiss()
            })
            .environmentObject(access)
        }
    }
}

/// Official CoinGecko coin images for an explicit allowlist of asset IDs.
/// No dynamic token-symbol lookup; unknown/offline assets retain a local glyph.
struct WalletAssetMark: View {
    let symbol: String
    let ticker: String
    @EnvironmentObject private var market: WalletMarketStore

    private var fallback: some View {
        Group {
            if ticker == "BTC" { Text("₿").font(.system(size: 29, weight: .medium)) }
            else if ticker == "USDT" { Text("₮").font(.system(size: 27, weight: .medium)) }
            else if ticker == "USDC" { Text("$").font(.system(size: 25, weight: .medium)) }
            else { Image(systemName: symbol).font(.system(size: 22, weight: .medium)) }
        }
        .foregroundStyle(WalletTheme.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var body: some View {
        Group {
            if let url = market.quote(ticker)?.imageURL {
                AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.18))) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit().padding(7)
                    case .empty, .failure: fallback
                    @unknown default: fallback
                    }
                }
            } else { fallback }
        }
        .frame(width: 47, height: 47)
        .background(WalletTheme.canvas, in: Circle())
        .accessibilityLabel(ticker)
    }
}

struct WalletAssetDetailView: View {
    @AppStorage("spyder.wallet.privacyHidden") private var privacyHidden = false
    let chain: SpyderChain
    let onSend: (SpyderChain) -> Void
    let onReceive: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chains: WalletChainStore
    @EnvironmentObject private var assets: WalletPublicAssetsStore
    @EnvironmentObject private var history: WalletActivityStore

    private var address: String { chains.address(for: chain) ?? "" }
    private var balance: Decimal? { assets.balances[chain] }
    private var explorer: URL? {
        let prefix: String
        switch chain {
        case .ethereum: prefix = "https://etherscan.io/address/"
        case .solana: prefix = "https://solscan.io/account/"
        case .bitcoin: prefix = "https://blockstream.info/address/"
        }
        guard !address.isEmpty else { return nil }
        return URL(string: prefix + address)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SpyderNavigationButton(symbol: "chevron.left", label: "Назад", action: { dismiss() })
                Spacer()
                Text(chain.name)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button {
                    guard !address.isEmpty else { return }
                    Task {
                        await assets.refresh(addresses: chains.addresses)
                        await history.refresh(addresses: [SpyderAddress(chain: chain, value: address)])
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(assets.loading || address.isEmpty)
                .accessibilityLabel("Обновить")
            }
            .foregroundStyle(WalletTheme.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(WalletTheme.canvas)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 13) {
                        WalletAssetMark(symbol: chain.symbol, ticker: chain.ticker)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(chain.name)
                                .font(.system(size: 23, weight: .bold))
                            Text(chain.ticker + " · Mainnet")
                                .font(.system(size: 13))
                                .foregroundStyle(WalletTheme.secondary)
                        }
                    }
                    .padding(.top, 12)
                    WalletCard {
                        VStack(alignment: .leading, spacing: 13) {
                            Text("Баланс")
                                .font(.system(size: 13))
                                .foregroundStyle(WalletTheme.secondary)
                            Text(privacyHidden ? "••••" : (balance.map {
                                WalletPublicAssetsStore.formatted($0) + " " + chain.ticker
                            } ?? "— " + chain.ticker))
                                .font(.system(size: 32, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(privacyHidden ? "••••" : usdBalance)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(WalletTheme.secondary)
                            if chain == .bitcoin, let confirmed = assets.bitcoinConfirmed {
                                Divider()
                                HStack {
                                    Text("Подтверждено")
                                    Spacer()
                                    Text(privacyHidden ? "••••" : WalletPublicAssetsStore.formatted(confirmed) + " BTC")
                                        .monospacedDigit()
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(WalletTheme.secondary)
                                if let pending = assets.bitcoinPendingDelta, pending != .zero {
                                    HStack {
                                        Text("Изменение в mempool")
                                        Spacer()
                                        Text(privacyHidden ? "••••" : WalletPublicAssetsStore.formatted(pending) + " BTC")
                                            .monospacedDigit()
                                    }
                                    .font(.system(size: 12))
                                    .foregroundStyle(WalletTheme.secondary)
                                }
                            }
                            if let failure = assets.failures[chain] {
                                Label("Баланс не удалось обновить: " + failure, systemImage: "wifi.exclamationmark")
                                    .font(.system(size: 12))
                                    .foregroundStyle(WalletTheme.secondary)
                            }
                        }
                    }
                    WalletMarketPanel(ticker: chain.ticker)
                    HStack(spacing: 12) {
                        action("Отправить", symbol: "arrow.up.right", primary: true) { onSend(chain) }
                        action("Получить", symbol: "arrow.down.left", primary: false) { onReceive() }
                    }
                    WalletCard {
                        VStack(alignment: .leading, spacing: 13) {
                            HStack {
                                Text("Адрес кошелька")
                                    .font(.system(size: 16, weight: .semibold))
                                Spacer()
                                Image(systemName: "qrcode")
                                    .foregroundStyle(WalletTheme.secondary)
                            }
                            Text(address.isEmpty ? "Адрес недоступен" : address)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(WalletTheme.secondary)
                                .textSelection(.enabled)
                                .privacySensitive()
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                UIPasteboard.general.setItems([["public.utf8-plain-text": address]], options: [
                                    .localOnly: true,
                                    .expirationDate: Date().addingTimeInterval(120)
                                ])
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            } label: {
                                Label("Копировать адрес", systemImage: "doc.on.doc")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .disabled(address.isEmpty)
                        }
                    }
                    activityCard
                    Label(LocalizedStringKey(chain.warning), systemImage: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(WalletTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(WalletTheme.ink)
        .navigationBarBackButtonHidden(true)
        .background(WalletTheme.canvas.ignoresSafeArea())
        .task(id: address) {
            guard !address.isEmpty else { return }
            await history.refresh(addresses: [SpyderAddress(chain: chain, value: address)])
        }
    }

    private var usdBalance: String {
        guard let balance, let price = assets.prices[chain] else { return "Курс USD недоступен" }
        return "≈ $" + WalletPublicAssetsStore.formatted(balance * price, fractionDigits: 2)
    }

    private func action(_ title: String, symbol: String, primary: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(LocalizedStringKey(title), systemImage: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .foregroundStyle(primary ? WalletTheme.contrast : WalletTheme.ink)
                .background(primary ? WalletTheme.accent : WalletTheme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var activityCard: some View {
        WalletCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("История операций")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    if history.loading.contains(chain) { ProgressView() }
                }
                let items = Array((history.activity[chain] ?? []).prefix(5))
                if items.isEmpty && !history.loading.contains(chain) {
                    Text(history.errors[chain] == nil ? "Нет загруженных операций" : "Не удалось загрузить историю")
                        .font(.system(size: 13))
                        .foregroundStyle(WalletTheme.secondary)
                }
                ForEach(items) { item in
                    Link(destination: item.explorerURL) {
                        HStack(spacing: 11) {
                            Image(systemName: item.state == .confirmed ? "checkmark.circle" : "clock")
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.direction + " · " + item.symbol)
                                    .font(.system(size: 14, weight: .medium))
                                Text(item.timestamp?.formatted(date: .abbreviated, time: .shortened) ?? "Дата неизвестна")
                                    .font(.system(size: 11))
                                    .foregroundStyle(WalletTheme.secondary)
                            }
                            Spacer()
                            Text(privacyHidden ? "••••" : (item.amount.map {
                                WalletPublicAssetsStore.formatted($0, fractionDigits: 6) + " " + item.symbol
                            } ?? "—"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(WalletTheme.ink)
                    }
                    if item.id != items.last?.id { Divider() }
                }
                if let explorer {
                    Divider()
                    Link(destination: explorer) {
                        Label("Открыть в обозревателе", systemImage: "arrow.up.right.square")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
            }
        }
    }
}

/// A token is identified by both chain and contract; only verified ERC-20 entries
/// can open this screen. It never implies that token signing is available.
struct WalletTokenDetailView: View {
    @AppStorage("spyder.wallet.privacyHidden") private var privacyHidden = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chains: WalletChainStore
    @EnvironmentObject private var assets: WalletPublicAssetsStore
    @EnvironmentObject private var spider: SpiderDevnetStore
    @State private var showingReceive = false
    @EnvironmentObject private var history: WalletActivityStore
    let token: WalletVerifiedToken

    private var address: String { chains.address(for: .ethereum) ?? "" }
    private var balance: Decimal? { assets.stablecoins[token.ticker] }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        WalletAssetMark(symbol: "dollarsign", ticker: token.ticker)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(token.name).font(.system(size: 24, weight: .bold))
                            Text(token.ticker + " · Ethereum ERC-20")
                                .font(.system(size: 13))
                                .foregroundStyle(WalletTheme.secondary)
                        }
                    }
                    WalletCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Баланс").font(.system(size: 13)).foregroundStyle(WalletTheme.secondary)
                            Text(privacyHidden ? "••••" : (balance.map {
                                WalletPublicAssetsStore.formatted($0, fractionDigits: 6) + " " + token.ticker
                            } ?? "— " + token.ticker))
                                .font(.system(size: 30, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                            if let amount = balance, let price = assets.stablecoinPrices[token.ticker] {
                                Text(privacyHidden ? "••••" : "≈ $" + WalletPublicAssetsStore.formatted(amount * price, fractionDigits: 2))
                                    .foregroundStyle(WalletTheme.secondary)
                            }
                        }
                    }
                    WalletMarketPanel(ticker: token.ticker)
                    Button { showingReceive = true } label: {
                        Label("Получить", systemImage: "arrow.down.left")
                            .spyderPrimaryButton()
                    }
                    .buttonStyle(.plain)
                    WalletCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Сеть получения").font(.system(size: 16, weight: .semibold))
                            Text("Ethereum Mainnet · ERC-20")
                                .font(.system(size: 13)).foregroundStyle(WalletTheme.secondary)
                            Divider()
                            Text("Контракт токена").font(.system(size: 14, weight: .semibold))
                            Text(token.contract)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(WalletTheme.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Адрес получения").font(.system(size: 14, weight: .semibold))
                            Text(address.isEmpty ? "Адрес недоступен" : address)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(WalletTheme.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .privacySensitive()
                        }
                    }
                    WalletCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("История операций")
                                .font(.system(size: 16, weight: .semibold))
                            let entries = Array((history.activity[.ethereum] ?? [])
                                .filter { $0.symbol == token.ticker }.prefix(5))
                            if entries.isEmpty {
                                Text("Нет загруженных операций. История токена может быть неполной.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(WalletTheme.secondary)
                            }
                            ForEach(entries) { item in
                                Link(destination: item.explorerURL) {
                                    HStack {
                                        Image(systemName: "arrow.left.arrow.right")
                                        Text(item.direction)
                                            .font(.system(size: 13, weight: .medium))
                                        Spacer()
                                        Text(privacyHidden ? "••••" : (item.amount.map {
                                            WalletPublicAssetsStore.formatted($0, fractionDigits: 6) + " " + token.ticker
                                        } ?? "—"))
                                            .font(.system(size: 12, weight: .medium))
                                            .monospacedDigit()
                                    }
                                    .foregroundStyle(WalletTheme.ink)
                                }
                            }
                        }
                    }
                    Label("Принимай только " + token.ticker + " в сети Ethereum ERC-20. Для будущей отправки понадобится ETH на комиссию.", systemImage: "exclamationmark.shield")
                        .font(.system(size: 12))
                        .foregroundStyle(WalletTheme.secondary)
                }
                .foregroundStyle(WalletTheme.ink)
                .padding(20)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .background(WalletTheme.canvas.ignoresSafeArea())
            .navigationTitle(token.ticker)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
        .sheet(isPresented: $showingReceive) {
            WalletReceiveView(preselected: .ethereum)
                .environmentObject(chains)
                .environmentObject(spider)
        }
    }
}
